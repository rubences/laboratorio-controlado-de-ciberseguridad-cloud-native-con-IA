import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from ai_apps import FOUNDATION_MODEL


PROFILE_PATH = Path(__file__).resolve().parent / "contracts" / "unified-stack-profile.json"


@lru_cache(maxsize=1)
def load_scenario_profile() -> dict[str, Any]:
    with PROFILE_PATH.open("r", encoding="utf-8") as profile_file:
        profile = json.load(profile_file)

    profile["foundation_model"] = FOUNDATION_MODEL
    return profile
