wget -qO- "http://weather.yahooapis.com/forecastrss?w=44418&u=c" | grep yweather:condition | sed -r 's/.*temp="([0-9]+)"(.*)/\1/'
