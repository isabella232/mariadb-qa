#!/bin/bash
# Created by Roel Van de Paar, MariaDB

LATEST_CORE=$(ls -t data/*core* 2>/dev/null | head -n1)
if [ -z "${LATEST_CORE}" ]; then
  echo "No core file found in data/*core* - exiting"
  exit 1
fi

ERROR_LOG=$(ls log/master.err 2>/dev/null | head -n1)
if [ -z "${ERROR_LOG}" ]; then
  echo "No error log found at log/master.err - exiting"
  exit 1
fi

RANDOM=`date +%s%N | cut -b14-19`  # Random entropy init
RANDF=$(echo $RANDOM$RANDOM$RANDOM | sed 's|.\(.......\).*|\1|')  # Random 7 digits filenumber

rm -f /tmp/${RANDF}.gdb*
gdb -q bin/mysqld $(ls data/*core*) >/tmp/${RANDF}.gdb1 2>&1 << EOF
  set pagination off
  set trace-commands off
  set frame-info short-location
  bt
  set print frame-arguments none
  set print repeats 0
  set print max-depth 0
  set print null-stop
  set print demangle on
  set print object off
  set print static-members off
  set print address off
  set print symbol-filename off
  set print symbol off
  set filename-display basename 
  set print array off
  set print array-indexes off
  set print elements 1
  set logging file /tmp/${RANDF}.gdb2
  set logging on
  bt
  set logging off
  quit
EOF

touch /tmp/${RANDF}.gdb3

# Assertion catch
# Assumes (which is valid for the pquery framework) that 1st assertion is also the last in the log
ASSERT="$(grep --binary-files=text -om1 'Assertion.*failed.$' ${ERROR_LOG} | sed 's|\.$||' | head -n1)"
if [ ! -z "${ASSERT}" ]; then
  echo "${ASSERT}" >> /tmp/${RANDF}.gdb3
else
  echo "NO_ASSERT" >> /tmp/${RANDF}.gdb3
fi

# Signal catch
if grep -E --binary-files=text -iq 'Program terminated with' /tmp/${RANDF}.gdb1; then
  grep 'Program terminated with' /tmp/${RANDF}.gdb1 | grep --binary-files=text -o 'with signal.*' | sed 's|with signal ||;s|\.$||' | head -n1 >> /tmp/${RANDF}.gdb3
elif grep -E --binary-files=text -iq '(sig=[0-9]+)' /tmp/${RANDF}.gdb1; then
  grep --binary-files=text '(sig=[0-9]\+)' /tmp/${RANDF}.gdb1 | grep --binary-files=text -o '[^ ]\+ (sig=[0-9]\+)' | head -n1 >> /tmp/${RANDF}.gdb3
else
  echo "NO_SIGNAL" >> /tmp/${RANDF}.gdb3
fi
rm -f /tmp/${RANDF}.gdb1

# Stack catch
grep --binary-files=text -A100 'signal handler called' /tmp/${RANDF}.gdb2 | grep --binary-files=text -vE '__GI_raise |__GI_abort |__assert_fail_base |__GI___assert_fail |(gdb)|signal handler called' | sed 's|^#[0-9]\+[ \t]\+||' | sed 's|(.*) at ||;s|:[ 0-9]\+$||' > /tmp/${RANDF}.gdb4
rm -f /tmp/${RANDF}.gdb2

# Cleanup do_command and higher frames, provided sufficient frames will remain
DC_LINE="$(grep --binary-files=text -n '^do_command' /tmp/${RANDF}.gdb4)"
DC_CLEANED=0
if [ ! -z "${DC_LINE}" ]; then
  DC_LINE=$(echo ${DC_LINE} | grep --binary-files=text -o '^[0-9]\+')
  if [ ! -z "${DC_LINE}" ]; then
    # Reduce stack lenght if there are at least 5 descriptive frames
    if [ ${DC_LINE} -ge 5 ]; then
      grep --binary-files=text -B100 '^do_command' /tmp/${RANDF}.gdb4 | grep --binary-files=text -v '^do_command' >> /tmp/${RANDF}.gdb3
      DC_CLEANED=1
    fi
  fi
fi
if [ ${DC_CLEANED} -eq 0 ]; then
  cat /tmp/${RANDF}.gdb4 >> /tmp/${RANDF}.gdb3
fi
rm -f /tmp/${RANDF}.gdb4

cat /tmp/${RANDF}.gdb3
rm -f /tmp/${RANDF}.gdb3