#!/usr/bin/env python3
"""Unit tests for the generated Android release-signing configuration."""

from __future__ import annotations

import unittest
from pathlib import Path

from configure_mobile_native import configure_release_signing


KOTLIN_GRADLE = """plugins {
    id("com.android.application")
}

android {
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
"""

GROOVY_GRADLE = """plugins {
    id 'com.android.application'
}

android {
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
"""


class ConfigureReleaseSigningTests(unittest.TestCase):
    def test_kotlin_dsl_requires_release_key_in_production(self) -> None:
        result = configure_release_signing(
            Path("build.gradle.kts"), KOTLIN_GRADLE
        )

        self.assertIn("ANDROID_RELEASE_STORE_FILE", result)
        self.assertIn('System.getenv("APP_ENV") == "production"', result)
        self.assertIn('create("release")', result)
        self.assertIn(
            "signingConfig = if (releaseSigningConfigured)", result
        )
        self.assertIn('signingConfigs.getByName("debug")', result)
        self.assertNotIn(r'\"release\"', result)

    def test_groovy_dsl_requires_release_key_in_production(self) -> None:
        result = configure_release_signing(Path("build.gradle"), GROOVY_GRADLE)

        self.assertIn("ANDROID_RELEASE_STORE_FILE", result)
        self.assertIn("System.getenv('APP_ENV') == 'production'", result)
        self.assertIn("signingConfigs.release : signingConfigs.debug", result)
        self.assertIn("storeFile file(releaseStoreFilePath)", result)

    def test_configuration_is_idempotent(self) -> None:
        once = configure_release_signing(
            Path("build.gradle.kts"), KOTLIN_GRADLE
        )
        twice = configure_release_signing(
            Path("build.gradle.kts"), once
        )
        self.assertEqual(once, twice)
        self.assertEqual(once.count("ESPANA_OUTDOOR_RELEASE_SIGNING"), 1)

    def test_unrecognized_release_signing_template_fails_closed(self) -> None:
        with self.assertRaises(SystemExit):
            configure_release_signing(
                Path("build.gradle.kts"),
                'plugins { id("com.android.application") }\nandroid { }\n',
            )


if __name__ == "__main__":
    unittest.main()
