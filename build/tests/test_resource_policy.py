import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from test_resources import comparison_environment


class ResourceComparisonTests(unittest.TestCase):
    def setUp(self):
        self.empty = {"air": {"processes": []}, "warnings": []}
        self.policy = {"after": {"memoryPriority": 5, "powerThrottling": {"highQoS": True}}}

    def eligible(self, profile="benchmark", before=None, after=None, policy=None):
        return comparison_environment(profile, before or self.empty, after or self.empty,
                                      self.policy if policy is None else policy)["performanceEligible"]

    def test_coexist_not_ranked_even_if_endpoints_empty(self):
        self.assertFalse(self.eligible("coexist"))

    def test_other_player_only_at_end_still_excludes_comparison(self):
        self.assertFalse(self.eligible(after={"air": {"processes": [{"pid": 123}]}}))

    def test_pressure_or_unavailable_policy_retains_functional_but_not_perf_evidence(self):
        self.assertFalse(self.eligible(before={"warnings": ["pressure"]}))
        self.assertFalse(self.eligible(policy={}))
        self.assertFalse(self.eligible(after={"error": "unavailable"}))

    def test_observed_clear_benchmark_can_be_paired(self):
        self.assertTrue(self.eligible())


if __name__ == "__main__":
    unittest.main()
