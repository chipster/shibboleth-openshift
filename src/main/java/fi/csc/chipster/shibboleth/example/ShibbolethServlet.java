package fi.csc.chipster.shibboleth.example;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.UnsupportedEncodingException;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map.Entry;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.catalina.connector.RequestFacade;

public class ShibbolethServlet extends HttpServlet {

	@Override
	protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {

		response.setContentType("text/html;charset=UTF-8");

		try (PrintWriter out = response.getWriter()) {
			out.println("<html>");
			out.println("<body>");
			
			// getting known attributes is easy
			
			out.println("<h4>Known attributes</h4>");
			out.println("<ul>");					
			out.println("<li>eppn: " + fixEncoding(request.getAttribute("SHIB_eppn").toString()));
			out.println("<li>cn: " + fixEncoding(request.getAttribute("SHIB_cn").toString()));								
			out.println("</ul>");
			
			
			/* Warning 1: Character encoding
			 * 
			 * Tomcat assumes the attributes are encoded in ISO-8859-1, although they are in
			 * fact UTF-8. There doesn't seem to be way to configure this in Tomcat, so use 
			 * fixEncoding() method to fix it here.
			 */
			
			/* 
			 * Warning 2: request.getAttributeNames()
			 * 
			 * Although request.getAttribute() returns these attributes,
			 * request.getAttributeNames() doesn't list them. 
			 * 
			 * You can find the longer explanation from the Tomcat issue tracker, 
			 * but the summary is that the servlet spec tests didn't foresee the possibility 
			 * of attributes being set internally instead of the 
			 * request.setAttribute() method.
			 */
			
			// find all attributes from the internals of Tomcat
			// could be useful for debugging, but will be fragile in Tomcat updates
			
			out.println("<h4>All attributes</h4>");
			out.println("<ul>");
			
			for (Entry<String, String> entry : getAllAttributes(request).entrySet()) {
				out.println("<li>" + entry.getKey() + ": " + entry.getValue());				
			}								
			out.println("</ul>");
							
			
			out.println("</body>");
			out.println("</html>");			
		}
	}			
	
	public static String fixEncoding(String input) throws UnsupportedEncodingException {
		return new String( input.getBytes("ISO-8859-1"), "UTF-8");
	}
	
	public static HashMap<String, String> getAllAttributes(HttpServletRequest request) throws UnsupportedEncodingException {
		
		HashMap<String, String> attrs = new HashMap<>();
		try {
			if (request instanceof RequestFacade) {
				
				Field f = RequestFacade.class.getDeclaredField("request");
				f.setAccessible(true);
				
				Object innerRequest = f.get(request);					
				
				if (innerRequest instanceof org.apache.catalina.connector.Request) {
					org.apache.catalina.connector.Request catalinaRequest = (org.apache.catalina.connector.Request) innerRequest;						
									
					for (String name : catalinaRequest.getCoyoteRequest().getAttributes().keySet()) {
						attrs.put(name, fixEncoding(request.getAttribute(name).toString()));
					}
				}						
			}						
		} catch (NoSuchFieldException | SecurityException | IllegalArgumentException | IllegalAccessException e) {
			System.err.println("can't find all attributes: " + e.getClass().getSimpleName() + " " + e.getMessage());
		}
		return attrs;
	}
}


