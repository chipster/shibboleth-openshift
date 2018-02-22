package fi.csc.chipster.shibboleth.example;

import java.io.File;

import org.apache.catalina.Context;
import org.apache.catalina.connector.Connector;
import org.apache.catalina.startup.Tomcat;

public class ShibbolethService {

	private static final String SHIBBOLETH_SERVLET_NAME = "shibboleth";
	private static final int PORT = 8012;
	private Tomcat tomcat;

	public void start() throws Exception {

		tomcat = new Tomcat();

		// ajp connector
		Connector ajpConnector = new Connector("AJP/1.3");
		ajpConnector.setPort(PORT);
		tomcat.getService().addConnector(ajpConnector);

		// servlet
		Context ctx = tomcat.addContext("", new File(".").getAbsolutePath());
		Tomcat.addServlet(ctx, SHIBBOLETH_SERVLET_NAME, new ShibbolethServlet());
		ctx.addServletMappingDecoded("/*", SHIBBOLETH_SERVLET_NAME);

		tomcat.start();   
	}

	public static void main(String[] args) throws Exception {
		ShibbolethService service = new ShibbolethService();
		
		service.start();
		service.tomcat.getServer().await();	
	}
}



