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
[x] MMDVMHost
[ ] rtlsdr
[ ] hackrf
[ ] bladerf
[ ] etc

Call Indicator:
[x] RX
[ ] TX
[ ] Slot
[x] Interrupt detection

Stats:
[x] call duration
[x] current speaker
[x] if a call is interrupted
[x] timestamp of last transmission from each radio
[ ] long term speaker stats (across multiple xmit sessions)
[ ] time slot decode
[ ] color code decode

Code Quality
[ ] Great
[ ] Good
[ ] Minimally Acceptable
[ ] Pretty Bad
[x] Literal Garbage
[ ] Unusable
[ ] Unexecutable
```
