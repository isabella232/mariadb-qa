#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ ! -r bin/mysqld ]; then
  echo "Assert: bin/mysqld not available, please run this from a basedir which had the SQL executed against it an crashed"
  exit 1
fi

if [ ! -r ../test_all ]; then
  echo "Assert: ../test_all not available - incorrect setup or structure"
  exit 1
fi

if [ ! -r ./in.sql ]; then
  echo "Assert: ./in.sql not available - incorrect setup or structure"
  exit 1
fi

if [ ! -r log/master.err ]; then
  echo "Assert: log/master.err not available, please run this from a basedir which had the SQL executed against it an crashed"
  exit 1
fi

CORE_COUNT=$(ls data/*core* 2>/dev/null | wc -l)
if [ ${CORE_COUNT} -eq 0 ]; then
  echo "Assert: no cores found at data/*core*, please run this from a basedir which had the SQL executed against it an crashed"
  exit 1
elif [ ${CORE_COUNT} -gt 1 ]; then
	echo "Assert: too many (${CORE_COUNT}) cores found at data/*core*, please run this from a freshly initited (./all) basedir which had the SQL executed against it an crashed"
  exit 1
fi

RANDOM=`date +%s%N | cut -b14-19`  # Random entropy init
RANDF=$(echo $RANDOM$RANDOM$RANDOM$RANDOM | sed 's|.\(..........\).*|\1|')  # Random 10 digits filenr

rm -f ../in.sql
if [ -r ../in.sql ]; then echo "Assert: ../in.sql still available after it was removed!"; exit 1; fi
cp in.sql ..
if [ ! -r ../in.sql ]; then echo "Assert: ../in.sql not available after copy attempt!"; exit 1; fi
cd ..
./test_all
cd -

SOURCE_CODE_REV="$(grep -om1 --binary-files=text "Source control revision id for MariaDB source code[^ ]\+" bin/mysqld 2>/dev/null | tr -d '\0' | sed 's|.*source code||;s|Version||')"
SERVER_VERSION="$(bin/mysqld --version | grep -om1 '[0-9\.]\+-MariaDB' | sed 's|-MariaDB||')"

gdb -q bin/mysqld $(ls data/*core*) >/tmp/${RANDF}.gdba 2>&1 << EOF
  set pagination off
  bt
  quit
EOF

echo '-------------------- BUG REPORT --------------------'
echo '{noformat}'
cat ./in.sql
echo -e '{noformat}\n'
echo -e 'Leads to:\n'
# Assumes (which is valid for the pquery framework) that 1st assertion is also the last in the log
ERROR_LOG=$(ls log/master.err 2>/dev/null | head -n1)
if [ ! -z "${ERROR_LOG}" ]; then
  ASSERT="$(grep --binary-files=text -m1 'Assertion.*failed.$' ${ERROR_LOG} | head -n1)"
  if [ ! -z "${ASSERT}" ]; then
    echo -e "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV}}\n${ASSERT}\n{noformat}\n"
  fi
fi

echo "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV}}"
grep -A999 'Core was generated by' /tmp/${RANDF}.gdba | grep -v '^(gdb)[ \t]*$' | grep -v '^[0-9]\+.*No such file or directory.$' | sed 's|(gdb) (gdb) |(gdb) bt\n|'
echo -e '{noformat}\n'
if [ -r ../test.results ]; then
  cat ../test.results
fi
echo '-------------------- /BUG REPORT --------------------'
echo 'Remember to action:'
echo '1) If no engine is specified, add ENGINE=InnoDB'
echo '2) Double check noformat version strings (10.5 default)'
echo '3) Add bug to known.strings as;'
~/t
cp in.sql ~/mariadb-qa/BUGS/in.sql
echo '5) This script copied in.sql to ~/mariadb-qa/BUGS/in.sql, rename as follows;'
echo 'mv ~/mariadb-qa/BUGS/in.sql ~/mariadb-qa/BUGS/MDEV-22000.sql'
