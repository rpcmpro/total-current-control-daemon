# Total Current Control of Mining Farms based on RPCM ME API

This script implements monitoring and automatic adaptation of load to
maximum available Amps capacity in Customer's power network. Customer can set
total available Amps for several RPCMs connected to a single phase.
Once the script notices that total Amps have been exceeded, it will start
turning off consumers according to survival priorities set up
in configuration file.
Another parameter to configure, is available Amps to try to return consumers
to operation automatically.
Once the script notices, that available Amps have exceeded indicated threshold
it will start turning on consumers according to survival priorities set in
configuration file.
Script can control multiple groups of RPCMs (typically can be used for
different power sources/phases)
Script has configurable stabilization delays to ensure that observed Amps value
is not a up- or down spike.
Script support near simultaneous turn off and turn on of outlets for devices
connected to RPCMs with multiple cables.
Script will not turn on outlets indicated as defaultState: "off"
Script will not attempt to turn off and then turn on outlets, that have admin
state on but actually are off due to short circuit or current overload.

## Installation

bundle install

edit totalCurrentControl.conf with your favorite text editor

## totalCurrentControl.conf file format

This file is pure JSON format

First level is name of Group

```
{
  "Group1" : {},
  "Group2" : {}
}
```

Second level (inside your Group name):

```
{
  "limitAmps": 90,
  "delayBeforeTurnOffSeconds": 10,
  "tryToTurnOnWhenAvailableAmps": 8,
  "delayBeforeTryToTurnOnSeconds": 60,
  "RPCMs": { "RybiyGlaz": {}, "DushistayaZhaba": {} }
}
```

RPCM level:

```
{
  "api_address":"10.210.1.148",
  "outlets": {
    "0": {}, "1": {}, "2": {}, "3": {}, "4": {},
    "5": {}, "6": {}, "7": {}, "8": {}, "9": {}
  }
}
```

Outlet level:

```
"0": { "survivalPriority": 3, "defaultState": "on", "comment": "3@RybiyGlaz" }
```

Survival Priorities are valid within group. Outlets with equal survival
priorities will be turn off and turn on nearly simultaneously.
Script will not turn off outlets with "defaultState": "off"
Comment can be any value for easy recognition of your powered devices

See example totalCurrentControl.conf file

## Usage

```
ruby totalCurrentControl.rb -h

Total Current Control Daemon for RPCM ME (http://rpcm.pro)

Usage: totalCurrentControl.rb [options]
    -d, --daemonize                  Daemonize and return control
    -l, --[no-]log                   Save log to file
    -v, --verbose                    Run verbosely
    -w, --working-directory PATH     Specify working directory (default current directory)
```

## License

This software is licensed under MIT License. See LICENSE.md

## Disclaimer

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
