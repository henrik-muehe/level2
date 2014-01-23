#!/bin/sh

# Add any build steps you need here

npm install

./node_modules/coffee-script/bin/coffee  --map --bare --compile --stdio < shield.coffee > shield.js
cat head.js shield.js > shield
chmod 755 shield