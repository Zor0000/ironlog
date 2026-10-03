import unittest

from select_e2e_simulator import select_pair


def phone(name: str) -> dict:
    return {"name": name, "identifier": name.replace(" ", "-")}


def runtime(version: str, devices: list[dict], available: bool = True) -> dict:
    return {"name": f"iOS {version}", "version": version,
            "identifier": f"ios-{version}", "isAvailable": available,
            "supportedDeviceTypes": devices}


class SimulatorSelectionTests(unittest.TestCase):
    def test_unordered_catalog_cannot_pair_new_phone_with_old_runtime(self):
        older = runtime("26.5", [phone("iPhone 16"), phone("iPhone 17 Pro")])
        newer = runtime("27.0", [phone("iPhone 18 Pro")], available=False)
        inventory = {"runtimes": [older, newer],
                     "devicetypes": [phone("iPhone 17 Pro"), phone("iPhone 18 Pro")]}
        self.assertEqual(select_pair(inventory), ("ios-26.5", "iPhone-17-Pro"))
        inventory["runtimes"].reverse()
        older["supportedDeviceTypes"].reverse()
        self.assertEqual(select_pair(inventory), ("ios-26.5", "iPhone-17-Pro"))

    def test_versions_are_numeric_and_newest_compatible_pair_wins(self):
        inventory = {"runtimes": [runtime("26.9", [phone("iPhone 16")]),
                                  runtime("26.10", [phone("iPhone 17 Pro Max"), phone("iPhone 17")])]}
        self.assertEqual(select_pair(inventory), ("ios-26.10", "iPhone-17"))

    def test_runtime_without_supported_phone_falls_back_or_fails(self):
        unsupported = runtime("27.0", [{"name": "iPad Pro", "identifier": "ipad"}])
        inventory = {"runtimes": [unsupported, runtime("26.5", [phone("iPhone 17")])]}
        self.assertEqual(select_pair(inventory), ("ios-26.5", "iPhone-17"))
        with self.assertRaisesRegex(ValueError, "No available iOS runtime"):
            select_pair({"runtimes": [unsupported]})
        with self.assertRaisesRegex(ValueError, "No available iOS runtime"):
            select_pair({"runtimes": [runtime("26.5", [phone("iPhone 17")], False)]})


if __name__ == "__main__":
    unittest.main()
