setlocal

set GF_HOME=D:\Users\NancarrowG\Work\glassfish5\glassfish4
set PATH=%GF_HOME%\glassfish\bin;%PATH%
set JAVA_HOME=c:\Program Files\Java\jdk1.8.0_121

call asadmin get --monitor=true server.resources.TestConnPoolBugPool.numconncreated-count
call asadmin get --monitor=true server.resources.TestConnPoolBugPool.numconnfree-current
call asadmin get --monitor=true server.resources.TestConnPoolBugPool.numconndestroyed-count

endlocal
