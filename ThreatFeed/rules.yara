// Spruce threat list: extra YARA rules
//
// Spruce downloads this file (at most once a day, over HTTPS) and runs its rules with the
// built-in YARA engine, next to Apple's XProtect rules, over the programs and scripts a
// malware scan looks at. A match only ever flags a file for the user to review; nothing is
// removed without the user confirming. The rules don't run on Apple-signed files or on
// programs with a valid developer signature (Developer ID, App Store).
//
// Rules here should name what they detect in their meta section:
//
//   rule Spruce_Example_Family_A
//   {
//       meta:
//           description = "Example.A"   // shown to the user: "Matches the Spruce threat list rule for Example.A"
//           family = "adload"           // a family id from feed.json or the built-in catalog (optional)
//           category = "adware"         // one of Spruce's threat categories (optional)
//           severity = "high"           // low, medium, high or critical (optional, default high)
//       strings:
//           $a = { 00 11 22 33 44 55 66 77 }
//       condition:
//           uint32(0) == 0xfeedfacf and $a
//   }
//
// Keep rules specific: a rule that matches one of Spruce's harmless sample files (an empty
// file, a bare program header, a tiny script…) is switched off automatically. Rules that
// use something the engine doesn't support (regular expressions, base64 strings, the pe,
// macho or math modules) are skipped on their own without affecting the rest of the file.
// See README.md for details.
//
// There are no extra rules yet.
