#!/usr/bin/awk -f

BEGIN {
  FS = ":"
  tests = 0
  tests_ok = 0
  reset = "\x1b[0m"
  bold = "\x1b[1m"
  blue = "\x1b[34m"
  grey = "\x1b[37m"
  green = "\x1b[32m"
  red = "\x1b[31m"
  yellow = "\x1b[33m"
}

/INFO:  SPEC:/ {
  print bold reset $6
}

/INFO:  TEST:/ {
  tests += 1
  print reset "\t" $6
}

/INFO:  OK:/ {
  tests_ok += 1
  print bold green "\t\tOK " reset substr($0, index($0, "OK: ") + 4) reset
}

/ERROR:  / {
  print bold red "\t\tERR " substr($0, index($0, "ERROR:  ") + 8) reset
}

/NOTICE:  / {
  print grey $0
}

!/(INFO|ERROR|NOTICE):  / {
  if($0 ~ /[A-Z]*/) {
    print grey $0 reset
  } else {
    print $0
  }
}

END {
  tests_error = tests - tests_ok
  print reset bold
  if(tests_error == 0) {
    print tests " tests, " green tests_ok " passed"
  } else {
    print tests " tests, " tests_ok " passed, " red (tests_error) " failed"
  }
  print reset
  exit tests_error
}

