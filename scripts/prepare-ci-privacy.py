"""Deny unused microphone input on a disposable Codemagic Mac before audio starts.

Only SimulatorTrampoline's current-user microphone row is changed. This does not
change SIP, file permissions, other clients, or the user's local Mac settings.
"""
import base64
import json
import os
from pathlib import Path
import sqlite3
import sys
import time


TARGET = ('kTCCServiceMicrophone', 'com.apple.CoreSimulator.SimulatorTrampoline', 0, 'UNUSED')
IDENTITY = ('service', 'client', 'client_type', 'indirect_object_identifier')
WHERE = 'service = ? AND client = ? AND client_type = ? AND indirect_object_identifier = ?'
REQUIRED_TYPES = {
    'service': 'TEXT', 'client': 'TEXT', 'client_type': 'INTEGER',
    'indirect_object_identifier': 'TEXT', 'auth_value': 'INTEGER',
    'auth_reason': 'INTEGER', 'auth_version': 'INTEGER',
    'flags': 'INTEGER', 'last_modified': 'INTEGER',
}


class PrivacySetupError(RuntimeError):
    pass


def inspect_schema(connection):
    """Accept the modern auth_value schema; unknown required fields fail closed."""
    table = connection.execute(
        "SELECT type FROM sqlite_master WHERE name = ?", ('access',)
    ).fetchone()
    if table != ('table',):
        raise PrivacySetupError('Existing TCC access table is missing or is not a table')
    columns = {row[1]: row for row in connection.execute('PRAGMA table_info(access)')}
    for name, expected_type in REQUIRED_TYPES.items():
        if name not in columns or columns[name][2].upper() != expected_type:
            raise PrivacySetupError(f'Unsupported TCC column: {name}')
    primary_key = tuple(row[1] for row in sorted(columns.values(), key=lambda row: row[5]) if row[5])
    if primary_key != IDENTITY:
        raise PrivacySetupError('Unsupported TCC access primary key')
    if 'indirect_object_identifier_type' in columns and columns['indirect_object_identifier_type'][2].upper() != 'INTEGER':
        raise PrivacySetupError('Unsupported TCC indirect object type')
    return columns


def snapshot_row(columns, row):
    if row is None:
        return None
    result = {}
    for name, value in zip(columns, row):
        result[name] = {'base64': base64.b64encode(value).decode('ascii')} if isinstance(value, bytes) else value
    return result


def deny_simulator_microphone(connection, *, now, record_before=None):
    """Portable transaction core: no platform, environment, or filesystem access.

    The optional callback receives only this exact permission row before the
    mutation. A callback failure aborts the transaction without changing TCC.
    """
    if connection.in_transaction:
        raise PrivacySetupError('Privacy setup requires its own transaction')
    connection.execute('BEGIN IMMEDIATE')
    try:
        columns = inspect_schema(connection)
        cursor = connection.execute('SELECT * FROM access WHERE ' + WHERE, TARGET)
        names = [item[0] for item in cursor.description]
        before = snapshot_row(names, cursor.fetchone())
        denial = {'auth_value': 0, 'auth_reason': 3, 'auth_version': 1, 'flags': 0}
        changed = before is None or any(before[name] != value for name, value in denial.items())
        values = dict(zip(IDENTITY, TARGET)) | denial | {'last_modified': int(now)}
        if 'indirect_object_identifier_type' in columns:
            values['indirect_object_identifier_type'] = 0
        if before is None:
            unsupported = [name for name, column in columns.items()
                           if column[3] and column[4] is None and name not in values]
            if unsupported:
                raise PrivacySetupError('Unsupported required TCC fields: ' + ', '.join(unsupported))
        if record_before is not None:
            record_before({'target': dict(zip(IDENTITY, TARGET)), 'before': before, 'changed': changed})
        if changed:
            if before is None:
                # Column names are a fixed allowlist; values are parameterized.
                field_names = ', '.join(values)
                placeholders = ', '.join('?' for _ in values)
                connection.execute(f'INSERT INTO access ({field_names}) VALUES ({placeholders})', tuple(values.values()))
            else:
                # Preserve code requirements and all unrelated/unknown columns.
                update = denial | {'last_modified': int(now)}
                assignments = ', '.join(name + ' = ?' for name in update)
                connection.execute('UPDATE access SET ' + assignments + ' WHERE ' + WHERE,
                                   tuple(update.values()) + TARGET)
        actual = connection.execute(
            'SELECT auth_value, auth_reason, auth_version, flags FROM access WHERE ' + WHERE, TARGET
        ).fetchone()
        if actual != (0, 3, 1, 0):
            raise PrivacySetupError('Microphone denial verification failed')
        connection.commit()
        return {'changed': changed, 'auth_value': actual[0], 'auth_reason': actual[1]}
    except BaseException:
        connection.rollback()
        raise


def write_evidence(path, snapshot):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Keep the first pre-change state when setup runs again in the same build.
    try:
        with path.open('x', encoding='utf-8') as output:
            json.dump(snapshot, output, indent=2)
            output.write('\n')
    except FileExistsError:
        existing = json.loads(path.read_text(encoding='utf-8'))
        if existing.get('target') != snapshot['target']:
            raise PrivacySetupError('Existing privacy evidence has a different target')


def main():
    if sys.platform != 'darwin' or not os.environ.get('CM_BUILD_ID', '').strip():
        raise PrivacySetupError('Privacy setup is restricted to a disposable Codemagic Mac')
    database = Path.home() / 'Library/Application Support/com.apple.TCC/TCC.db'
    if not database.is_file():
        raise PrivacySetupError('Current-user TCC database does not exist; refusing to create one')
    with sqlite3.connect(database.resolve().as_uri() + '?mode=rw', uri=True, timeout=5) as connection:
        result = deny_simulator_microphone(
            connection, now=int(time.time()),
            record_before=lambda snapshot: write_evidence(Path('build-tests/ci-privacy-before.json'), snapshot),
        )
    print('CI privacy: SimulatorTrampoline microphone denied; ' +
          ('permission row updated' if result['changed'] else 'already denied'), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (PrivacySetupError, sqlite3.Error, OSError, ValueError) as error:
        print(f'CI privacy setup failed: {error}', file=sys.stderr)
        sys.exit(1)
