# dmrrr
Digital Metadata Receive, Record, and Report

This horrifying bit of code reads the dmesgtail from a tytera md-3[89]0 radio using https://github.com/travisgoodspeed/md380tools and prints out entertaining stats about who speaks and for how long.  The plan is to improve the feature set and stat collection, as well as improve the UI and add a web ui.  At some point we plan to switch to collecting information with sdr, however, at the start of this project dsd didn't decode who the call was from or to, and dmrdecode didn't show call start/end so it was impossible to collect the desired stats.

```
Decode:
[x] DMR
[ ] P25

Radio:
[x] Tytera MD380
[x] Tytera MD390
[ ] rtlsdr
[ ] hackrf
[ ] bladerf
[ ] etc

Stats:
[x] call duration
[.] current speaker (listed in the logs because the main ui isn't started yet)
[x] if a call is interrupted
[ ] long term speaker stats (across multiple xmit sessions)
[ ] time slot decode
[ ] color code decode
```
