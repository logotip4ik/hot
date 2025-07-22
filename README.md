# Hot

Simple process runner.

Well there are probably a ton of such things on GitHub, but i wasn't able to find simply:

> give a command i will re-run it

so, why not build it ? (i hope it works, will try in my production...)

## Usage

```sh
hot - simple process supervisor

Usage: hot [command] [[...args]]

Optional arguments:
  --maxRetries - number of retries to do, accepts `number` or `null` (default is 10)
  --retryDelay - delay between each retries in ms (default is 500ms)

Example:
 hot ./my-bot --maxRetries 10 --retryDelay 100
```
