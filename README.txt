Connection Pool bug occurs when Connection Validation is enabled and "On Any Failure  Close All Connections" option is used



For JDBC and Connector Connection Pools, a connection pool bug occurs when Connection Validation is enabled and "On Any Failure  Close All Connections" is used, and a connection is retrieved (getConnection()) which fails validation. The bug is that in this case, too many connections are created and destroyed in rebuilding the connection pool, and one connection is created and marked in-use which can then never be closed and so reduces the number of free connections available in the pool.

This bug all stems from an obvious problem in the source code, in the "getResourceFromPool" method of the "com.sun.enterprise.resource.pool.ConnectionPool" class (connectors-runtime.jar).
This method has the following code. Note that in the case in question, "failAllConnections" is true, and the call to "isConnectionValid" returns false.



        try{
            while ((h = ds.getResource()) != null) {

                if (h.hasConnectionErrorOccurred()) {
                    ds.removeResource(h);
                    continue;
                }

                if (matchConnection(h, alloc)) {

                    boolean isValid = isConnectionValid(h, alloc);
                    if (h.hasConnectionErrorOccurred() || !isValid) {
                        if (failAllConnections) {
                            createSingleResourceAndAdjustPool(alloc, spec);
                            //no need to match since the resource is created with the allocator of caller.
                            break;
                        } else {
                            ds.removeResource(h);
                            //resource is invalid, continue iteration.
                            continue;
                        }
                    }
                    if(h.isShareable() == alloc.shareableWithinComponent()){
                        // got a matched, valid resource
                        result = h;
                        break;
                    }else{
                        freeResources.add(h);
                    }
                } else {
                    freeResources.add(h);
                }
            }
        }finally{
            //return all unmatched, free resources
            for (ResourceHandle freeResource : freeResources) {
                ds.returnResource(freeResource);
            }
            freeResources.clear();
        }

        if (result != null) {
            // set correct state
            setResourceStateToBusy(result);
        } else {
            result = resizePoolAndGetNewResource(alloc);
        }
        return result;



You will notice that the return value of the "createSingleResourceAndAdjustPool" method call is NOT USED. This is the cause of the bug. It is MEANT to be assigned to the "result" variable. Because the resource created by the "createSingleResourceAndAdjustPool" method is not assigned to "result", then "result" is null, and the code after the while loop thus calls "resizePoolAndGetNewResource", as if no suitable resource was found in the pool and the pool needs to be resized (which of course is NOT the case at all).

[I looked back at the history of changes to this source file, and found that originally the return value of "createSingleResourceAndAdjustPool" was erroneously assigned to a different variable to "result", and that variable was thereafter not referenced in the source code. Some time after, someone ran the "FindBugs" tool over the source code, which reported that that variable was set but never referenced, so the variable assignment was removed. It silenced FindBugs, but didn't address the actual problem.]

In addition to the missing assignment of the return value from "createSingleResourceAndAdjustPool", I also found that the "getNewResource" method (called by the "createSingleResourceAndAdjustPool" method) is not incrementing the NumConnFree monitoring count.




I have developed a small test application (servlet) that can be used to reproduce the Connection Pool bug.
The following files are included:

TestConnPoolBug.war:   the test application
setup.bat:             setup the JDBC resources and pool monitoring and deploy the application
cleanup.bat:           remove the JDBC resources, pool monitoring settings and undeploy the application
do_mon.bat:            display some monitoring statistics for the connection pool
restart_db.bat:        stop and restart the JavaDB database

For simplicity, the test application uses JavaDB that comes with Glassfish (with minor modifications to the connection pool settings, any database supported by Glassfish may be used).

The test application code simply gets 5 connections then closes them, as shown in the servlet source code snippet below. The full source code is included in the WAR file. 


    /**
     * Processes requests for both HTTP <code>GET</code> and <code>POST</code>
     * methods.
     *
     * @param request servlet request
     * @param response servlet response
     * @throws ServletException if a servlet-specific error occurs
     * @throws IOException if an I/O error occurs
     */
    protected void processRequest(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("text/html;charset=UTF-8");
        try (PrintWriter out = response.getWriter()) {

            out.println("<!DOCTYPE html>");
            out.println("<html>");
            out.println("<head>");
            out.println("<title>Servlet TestConnPoolBugServlet</title>");            
            out.println("</head>");
            out.println("<body>");

            Connection[] connections = new Connection[5];
            
            try {
                InitialContext e = new InitialContext();
                DataSource ds = (DataSource)e.lookup("jdbc/TestConnPoolBug");

                for (int iCon = 1; iCon <= connections.length; iCon++) {
                    out.println("<h1>Getting connection " + iCon + "</h1>");
                    try {
                        connections[iCon - 1] = ds.getConnection();
                    } catch (Exception ex) {
                        out.println("<h1>ERROR: " + ex.getMessage() + "</h1>");
                    }
                }

            } catch (NamingException nex) {
               out.println("<h1>ERROR: " + nex.getMessage() + "</h1>");
            } finally {
                int iCon = 1;
                for (Connection con : connections) {
                    if (con != null) {
                        out.println("<h1>Closing connection " + iCon + "</h1>");
                        try {
                            con.close();
                        } catch (Exception ex) {
                        }
                    }
                    iCon++;
                }
            }
            
            out.println("</body>");
            out.println("</html>");
        }
    }
    
    


Please follow the steps below to reproduce the problem:

1) Make sure Glassfish is running (e.g. "asadmin start-domain")
2) Setup the resources, pool monitoring and deploy the application by running “setup.bat”. 
3) Open the following URL in your browser:   http://localhost:8080/TestConnPoolBug
4) Firstly, just click on the “TestConnPoolBugServlet” link. You should see the following output:

Getting connection 1
Getting connection 2
Getting connection 3
Getting connection 4
Getting connection 5
Closing connection 1
Closing connection 2
Closing connection 3
Closing connection 4
Closing connection 5


You can run this multiple times and get the same result. If “do_mon.bat” is run, the following monitoring statistics are output:

server.resources.TestConnPoolBugPool.numconncreated-count = 5
server.resources.TestConnPoolBugPool.numconnfree-current = 5
server.resources.TestConnPoolBugPool.numconndestroyed-count = 0

This is the normal case, with expected monitoring statistics for the connection pool.


To reproduce the bug, it is required to stop and restart the database after the connection pool is built – so the pool connections are invalidated - then invoke the test servlet. Follow the steps below:

5) Now, navigate back to: http://localhost:8080/TestConnPoolBug
6) Stop and restart the database (run “restart_db.bat”). This invalidates the connections in the connection pool. Because the pool uses the “On Any Failure Close All Connections” flag, the first attempt to get a connection will first cause all existing connections in the pool to be destroyed and then the pool connections will be re-created.
7) Click on the “TestConnPoolBugServlet” link, to invoke the test code.

Due to the Connection Pool bug, you see the following output (it will first hang for about a minute - please wait):

Getting connection 1
Getting connection 2
Getting connection 3
Getting connection 4
Getting connection 5
ERROR: Error in allocating a connection. Cause: In-use connections equal max-pool-size and expired max-wait-time. Cannot allocate more connections.
Closing connection 1
Closing connection 2
Closing connection 3
Closing connection 4


Note that “Connection 5” failed because all the connections in the pool have already been used (this should NOT happen, as the minimum and maximum poolsize is 5).
Run “do_mon.bat” to see some important connection pool monitoring statistics:

server.resources.TestConnPoolBugPool.numconncreated-count = 13
server.resources.TestConnPoolBugPool.numconnfree-current = 4
server.resources.TestConnPoolBugPool.numconndestroyed-count = 8


The above statistics definitely shows problems in the pooling and pooling statistics. Too many connections have been created and destroyed, and only 4 connections are left free.


I have developed the patch below which corrects the pooling problems that I found.



Index: main/appserver/connectors/connectors-runtime/src/main/java/com/sun/enterprise/resource/poolConnectionPool.java
=====================================================================================================================
--- ConnectorService.java       (revision 57363)
+++ ConnectorService.java       (working copy)
@@ -722,13 +722,13 @@
 
                 if (matchConnection(h, alloc)) {
 
                     boolean isValid = isConnectionValid(h, alloc);
                     if (h.hasConnectionErrorOccurred() || !isValid) {
                         if (failAllConnections) {
-                            createSingleResourceAndAdjustPool(alloc, spec);
+                            result = createSingleResourceAndAdjustPool(alloc, spec);
                             //no need to match since the resource is created with the allocator of caller.
                             break;
                         } else {
                             ds.removeResource(h);
                             //resource is invalid, continue iteration.
                             continue;
@@ -876,16 +876,17 @@
         ResourceHandle handle = ds.getResource();
         if (handle != null) {
             ds.removeResource(handle);
         }
 
         ResourceHandle result = getNewResource(alloc);
-        if (result != null) {
-            alloc.fillInResourceObjects(result);
-            result.getResourceState().setBusy(true);
-        }
+        // The code below has been commented-out because it is effectively being run AGAIN by the caller
+        //if (result != null) {
+        //   alloc.fillInResourceObjects(result);
+        //   result.getResourceState().setBusy(true);
+        //}
 
         return result;
     }
 
 
     /**
@@ -1243,13 +1244,15 @@
         if (poolLifeCycleListener != null) {
             poolLifeCycleListener.connectionValidationFailed(1);
         }
     }
 
     private ResourceHandle getNewResource(ResourceAllocator alloc) throws PoolingException {
-        ds.addResource(alloc, 1);
+        // The wrapper method addResource() needs to be called instead of ds.addResource(), so that NumConnFree gets incremented after creating the new resource
+        //ds.addResource(alloc, 1);
+        addResource(alloc);
         return ds.getResource();
     }
 
 
     private ResourceState getResourceState(ResourceHandle h) {
         return h.getResourceState();





If the test is run with the above patch applied to Glassfish, the following (correct) output is obtained:


Getting connection 1
Getting connection 2
Getting connection 3
Getting connection 4
Getting connection 5
Closing connection 1
Closing connection 2
Closing connection 3
Closing connection 4
Closing connection 5


The following (correct) monitoring statistics are output by running “do_mon.bat”:

server.resources.TestConnPoolBugPool.numconncreated-count = 11
server.resources.TestConnPoolBugPool.numconnfree-current = 5
server.resources.TestConnPoolBugPool.numconndestroyed-count = 6


[On the first getConnection() call, an invalid pool connection is detected, so all connections in the pool are destroyed and then re-created. The createSingleResourceAndAdjustPool() method then creates a new connection and replaces a free connection in the pool, destroying it.]




