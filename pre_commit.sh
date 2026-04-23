#!/bin/bash

set -e

npm i
npm run lint:fix
npm run format
npm run build
npm run test

# Regenerate Gleam docs HTML.
cd e2e-test
gleam docs build
cd ..
