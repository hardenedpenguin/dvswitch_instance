<img src="https://github.com/hardenedpenguin/dvswitch_instance/blob/main/PXL_20250214_230436698.jpg" width="500" height="300">

This is a simple script that will allow you to generate multiple instance of dvswitch.

It currently supports 2 thru 5 for instance number. All ports and information displayed before editing
each file is generated and checked to ensure nothing else is using the ports. If you edit the file with
the information that is provided to you when script runs, there is no need you can not generate an additional
instance of dvswitch that works as you would expect.

If your wanting a second instance simply

```
sudo ./dvswitch_instance.sh 2
```
You can do this all the way up to 5, script is geared toward DMR but can be modified for 
all bridges.
