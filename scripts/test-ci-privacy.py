"""Portable tests for the narrowly scoped CI permission transaction."""
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location('ci_privacy', Path(__file__).with_name('prepare-ci-privacy.py'))
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)
SCHEMA = '''CREATE TABLE access (
 service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL,
 auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL,
 csreq BLOB, policy_id INTEGER, indirect_object_identifier_type INTEGER,
 indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB,
 flags INTEGER, last_modified INTEGER NOT NULL,
 PRIMARY KEY (service, client, client_type, indirect_object_identifier)
)'''


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'TCC.db'
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        self.db.execute(SCHEMA)
        self.db.commit()

    def insert(self, target=privacy.TARGET, auth=2, csreq=None):
        self.db.execute('''INSERT INTO access
            (service, client, client_type, indirect_object_identifier,
             auth_value, auth_reason, auth_version, flags, last_modified, csreq)
            VALUES (?, ?, ?, ?, ?, 0, 1, 0, 17, ?)''', tuple(target) + (auth, csreq))
        self.db.commit()

    def rows(self):
        return self.db.execute('SELECT * FROM access ORDER BY service, client, client_type, indirect_object_identifier').fetchall()

    def test_denial_changes_only_exact_allow_row_and_preserves_metadata(self):
        self.insert(csreq=b'code requirement')
        for target in (
            ('kTCCServiceCamera', *privacy.TARGET[1:]),
            (privacy.TARGET[0], 'another.client', 0, 'UNUSED'),
            (privacy.TARGET[0], privacy.TARGET[1], 1, 'UNUSED'),
            (*privacy.TARGET[:3], 'another-object'),
        ):
            self.insert(target)
        unrelated_before = [row for row in self.rows() if tuple(row[i] for i in (0, 1, 2, 9)) != privacy.TARGET]
        evidence = []
        result = privacy.deny_simulator_microphone(self.db, now=100, record_before=evidence.append)
        self.assertTrue(result['changed'])
        self.assertEqual(evidence[0]['before']['auth_value'], 2)
        self.assertEqual(evidence[0]['before']['csreq'], {'base64': 'Y29kZSByZXF1aXJlbWVudA=='})
        self.assertEqual(self.db.execute('SELECT auth_value, auth_reason, auth_version, flags, last_modified, csreq FROM access WHERE ' + privacy.WHERE, privacy.TARGET).fetchone(),
                         (0, 3, 1, 0, 100, b'code requirement'))
        self.assertEqual(unrelated_before, [row for row in self.rows() if tuple(row[i] for i in (0, 1, 2, 9)) != privacy.TARGET])

    def test_new_row_uses_modern_schema_defaults_and_is_idempotent(self):
        self.db.execute("ALTER TABLE access ADD COLUMN boot_uuid TEXT NOT NULL DEFAULT 'UNUSED'")
        self.db.execute('ALTER TABLE access ADD COLUMN last_reminded INTEGER NOT NULL DEFAULT 0')
        self.db.commit()
        evidence = []
        privacy.deny_simulator_microphone(self.db, now=100, record_before=evidence.append)
        self.assertIsNone(evidence[0]['before'])
        self.assertEqual(self.db.execute('SELECT boot_uuid, last_reminded, indirect_object_identifier_type FROM access').fetchone(), ('UNUSED', 0, 0))
        before = self.rows()
        result = privacy.deny_simulator_microphone(self.db, now=200)
        self.assertFalse(result['changed'])
        self.assertEqual(self.rows(), before)

    def test_evidence_failure_rolls_back_without_changing_permission(self):
        self.insert()
        before = self.rows()
        def fail(_):
            raise OSError('evidence unavailable')
        with self.assertRaises(OSError):
            privacy.deny_simulator_microphone(self.db, now=100, record_before=fail)
        self.assertEqual(self.rows(), before)

    def test_missing_and_legacy_schema_refused(self):
        self.db.execute('DROP TABLE access')
        for create in (None, 'CREATE TABLE access (service TEXT, client TEXT, allowed INTEGER)'):
            if create:
                self.db.execute(create)
            self.db.commit()
            with self.assertRaises(privacy.PrivacySetupError):
                privacy.deny_simulator_microphone(self.db, now=100)

    def test_unknown_required_field_refuses_insertion(self):
        self.db.execute('DROP TABLE access')
        self.db.execute(SCHEMA.replace('csreq BLOB,', 'new_required TEXT NOT NULL, csreq BLOB,'))
        self.db.commit()
        with self.assertRaises(privacy.PrivacySetupError):
            privacy.deny_simulator_microphone(self.db, now=100)
        self.assertEqual(self.rows(), [])

    def test_incompatible_primary_key_refused(self):
        self.db.execute('DROP TABLE access')
        self.db.execute(SCHEMA.replace('PRIMARY KEY (service, client, client_type, indirect_object_identifier)', 'PRIMARY KEY (service, client)'))
        self.db.commit()
        with self.assertRaises(privacy.PrivacySetupError):
            privacy.deny_simulator_microphone(self.db, now=100)

    def test_platform_and_ci_guards_run_before_filesystem_access(self):
        for platform, environment in (('win32', {'CM_BUILD_ID': 'test'}), ('darwin', {}), ('darwin', {'CM_BUILD_ID': '  '})):
            with mock.patch.object(privacy.sys, 'platform', platform), mock.patch.dict(privacy.os.environ, environment, clear=True), mock.patch.object(privacy.Path, 'home') as home:
                with self.assertRaises(privacy.PrivacySetupError):
                    privacy.main()
                home.assert_not_called()

    def test_missing_database_refused_without_creation(self):
        with mock.patch.object(privacy.sys, 'platform', 'darwin'), mock.patch.dict(privacy.os.environ, {'CM_BUILD_ID': 'test'}, clear=True), mock.patch.object(privacy.Path, 'home', return_value=Path(self.directory.name)):
            with self.assertRaises(privacy.PrivacySetupError):
                privacy.main()
        self.assertFalse((Path(self.directory.name) / 'Library').exists())

    def test_evidence_preserves_original_on_rerun(self):
        path = Path(self.directory.name) / 'evidence.json'
        snapshot = {'target': dict(zip(privacy.IDENTITY, privacy.TARGET)), 'before': {'auth_value': 2}, 'changed': True}
        privacy.write_evidence(path, snapshot)
        privacy.write_evidence(path, snapshot | {'before': {'auth_value': 0}, 'changed': False})
        self.assertEqual(json.loads(path.read_text()), snapshot)


if __name__ == '__main__':
    unittest.main()
