# Telamon OS: older($c; $o) is true when image $c ({version, timestamp}) is
# older than $o. Versions compare as numbers split on . and - (44.20261008-2),
# with missing parts 0; times as RFC 3339 UTC to the second. A signal that
# can't be read is left out. Older means the version or the build time says
# so and neither says the opposite. Used by update-stage-condition and
# update-stage; Telamon Updater's helper refuses such an image the same way
# (atlas_core::bootc::ImageStatus::is_older_than).
def vnum: try [splits("[.-]") | tonumber] catch null;
def pad($n): . + [range($n - length) | 0];
def vcmp($a; $b): ($a | vnum) as $x | ($b | vnum) as $y
	| if $x == null or $y == null then null
	  else ([($x | length), ($y | length)] | max) as $n
	  | ($x | pad($n)) as $x | ($y | pad($n)) as $y
	  | if $x < $y then -1 elif $x > $y then 1 else 0 end end;
def tkey: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}.*Z$")
	then .[0:19] else null end;
def tcmp($a; $b): ($a | tkey) as $x | ($b | tkey) as $y
	| if $x == null or $y == null then null
	  elif $x < $y then -1 elif $x > $y then 1 else 0 end;
def older($c; $o): [vcmp($c.version; $o.version), tcmp($c.timestamp; $o.timestamp)]
	| any(.[]; . == -1) and all(.[]; . != 1);
