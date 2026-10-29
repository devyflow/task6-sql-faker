from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent


class ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = (ROOT / "schema.sql").read_text(encoding="utf-8")
        cls.app = (ROOT / "app.py").read_text(encoding="utf-8")

    def test_generation_is_a_database_procedure(self):
        self.assertIn("CREATE OR REPLACE PROCEDURE generate_people_batch", self.sql)
        self.assertIn("CALL generate_people_batch", self.app)

    def test_deterministic_hash_primitives_exist(self):
        self.assertIn("FUNCTION hash_uniform", self.sql)
        self.assertIn("FUNCTION hash_normal", self.sql)
        self.assertIn("md5(p_seed::text", self.sql)

    def test_required_generated_fields_exist(self):
        for field in ("full_name", "middle_name", "eye_color", "height_cm", "weight_kg", "latitude", "longitude", "phone", "email"):
            self.assertIn(field, self.sql)

    def test_next_batch_is_part_of_deterministic_key(self):
        self.assertIn("batch_index", self.sql)
        self.assertIn("v_batch_index::bigint*1000000", self.sql)

    def test_web_layer_does_not_generate_fake_values(self):
        for forbidden in ("random.", "from faker", "import faker", "numpy", "uuid4("):
            self.assertNotIn(forbidden, self.app.lower())


if __name__ == "__main__":
    unittest.main()
