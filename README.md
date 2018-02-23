# Shibboleth authentication in OpenShift for Java

## Introduction

The [`deploy-shibboleth.bash`](deploy-shibboleth.bash) script deploys and configures an OpenShift container for doing Haka authentication for a simple Java application.

## Usage
### Prerequisites

Check out this repository
```bash
git clone https://github.com/chipster/shibboleth-openshift.git
cd shibboleth-openshift
```

Check that you are logged in and in an OpenShfit project
```bash
oc project
```
> Using project "chipster-dev" on server "https://rahti.csc.fi:8443"

The script assumes you have the command line tools `oc` (OpenShift command line client), `wget`, `jq` (for parsing JSON) and `gradle` (Java build) already installed on your development machine.

### Interactive

Run the script
```bash
bash deploy-shibboleth.bash
```

Accept the defaults by hitting enter or set your own values. 

> set name [shibboleth]:

This will be the name for your pod and route and will be used as a prefix many names in OpenShfit. Make sure it doesn't clash with anything you already have in the project. 

> set cert_dir [~/shibboleth_keys/chipster-dev.rahti.csc.fi]:

The folder for the private key and certificate used by Shibboleth. New keys are generated, if they are not there already.

> set metadata [https://haka.funet.fi/metadata/haka_test_metadata_signed.xml]: 	
>
> set metadata_cert [https://wiki.eduuni.fi/download/attachments/27297785/haka_testi_2015_sha2.crt]: 	
>
> set discovery_service [https://testsp.funet.fi/shibboleth/WAYF]: 	
>
> set attribute_map [https://wiki.eduuni.fi/download/attachments/27297794/attribute-map.xml]:

URL's for the Haka test federation. The *attribute_map* is valid also for the production Haka. 

> set support [your@support.email]:

Your support email address which is shown in error pages.


 ### Scripts
 
All settings can be set with paramaters. The script will still ask for all the settings that weren't set. Check the parameter names from the interactive output above.
 
```bash
bash deploy-shibboleth.bash --name haka --support my@support.email
```

### Register

The authentication doesn't work until your service is registered, but the script will print instructions for you. 

```
Register the service in Haka resource registry https://rr.funet.fi/rr

** Organiztion information
Select your organization.

** SP Basic Information
Entity Id                                             https://haka-chipster-dev.rahti-app.csc.fi
Service Name (Finnish)                                <fill-in>
Service Description (Finnish)                         <fill-in>
Service Login Page URL                                https://haka-chipster-dev.rahti-app.csc.fi/Shibboleth.sso/Login
Discovery Response URL                                https://haka-chipster-dev.rahti-app.csc.fi/Shibboleth.sso/Login
urn:oasis:names:tc:SAML:2.0:nameid-format:transient   x
eduGain                                               <e.g. unselected>
Haka                                                  <e.g. unselected>
Haka test                                             <e.g. selected>

** SP SAML Endpoints
URL index #1                                          https://haka-chipster-dev.rahti-app.csc.fi/Shibboleth.sso/SAML2/POST

** Certificates
Copy the contents of the file ~/shibboleth_keys/chipster-dev.rahti.csc.fi/sp-cert.pem to the text field (without the first and 
last line).

** Requested Attributes
The test application uses these two attributes

eduPersonPrincipalName                                x    Technical user identifier
cn                                                    x    Human-readable name of the user

Select the additional attributes you need and explain why. See
- https://rr.funet.fi/haka/ (your own information)
- https://testsp.funet.fi/haka/ (you will get the test credentials after the registration)
- https://wiki.eduuni.fi/display/CSCHAKA/funetEduPersonSchema2dot2

In Test-Haka, select at least the cn attribute, becuase the test user's name contains an 
accented character, which allows us to test a character encoding issue later.

** UI Extensions
None

** Contact Information
Contact type                                          Technical
First Name                                            <fill-in>
Last Name                                             <fill-in>
E-Mail                                                chipster@csc.fi
Contact type                                          Support
First Name                                            <fill-in>
Last Name                                             <fill-in>
E-Mail                                                chipster@csc.fi
--------------------------------------------------------------------------------------------
```

Click *Submit SP Description* and you should get an email when the federation has processed your registration. The email contains the credentials of the test account, which you can use to log in to your service. Navigate a browser to `SERVICE_URL/Shibboleth.sso/Login`. You should be redirected first to the Discovery Service and then to the Login form. Fill in the credentials of the test user and you should be back in your own service. See `SERVICE_URL/Shibboleth.sso/Session` and now you should have an active authentication session. You can logout by going to `SERVICE_URL/Shibboleth.sso/Logout`.

## Troubleshooting

If this doesn't work, see Apache log file
```bash
oc rsh dc/shibboleth cat /var/log/apache2/error.log
```

*shibd* log file
```bash
oc rsh dc/shibboleth cat /var/log/shibboleth/shibd.log
```

Your service's metadata
```bash
curl SERVICE_URL/Shibboleth.sso/Metadata
```

## Making changes

There are two ways to replace the current demo application with your own. You can either make a separate project for your own application or do the modifications directly to the fork of this repository.

This example shows how to get the authentication information to a small example service written in Java. What you do then with this information depends on the architectural style of your application. If you are building a monolithic application, you will probably build your whole application behind this Apache web server. On the other hand, in a microservice architecture this would be just another simple microservice, which will only trigger your own authentication system.

### Different repository

Keeping your own application in a separate repository makes it easy pull latest versions of this project, but more difficult to make radical changes to the configuration.

Create a new git repo for you project, run the `deploy-shibboleht.bash` script to setup the demo application.

```bash
bash ../shibboleth-openshift/deploy-shibboleth.bash --name haka --support my@support.email
```

Replace the *shibboleth-java* build with your own (but it must be based on the image "shibboleth").

```bash
oc new-build . -D - < dockerfiles/shibboleth-java/Dockerfile --name shibboleth-java && sleep 1 && oc logs -f bc/shibboleth-java
```

Configure the deployment config created by the script (called "haka" in this example) like you wish.
 
```bash
oc set volume dc/haka --add -t emptyDir --mount-path /opt/chipster-web-server/logs
```

### Fork this repository

It's simple to fork this repository in GitHub and start making changes, but then the merging the latest changes from this repository requires more work.

Most likely you have to update the dockerfile every now and then. You can do it in *OpenShift console* (the OpenShift web app), but I prefer keeping the original on my laptop for easier version control. It pays off to build [a small bash script](update_dockerfile.bash) for replacing the dockerfile in OpenShift with your local version like this:
 
```bash 
  bash update_dockerfile.bash shibboleth
  oc start-build shibboleth --follow
```
```bash
  bash update_dockerfile.bash shibboleth-java
  oc start-build shibboleth-java https://github.com/chipster/shibboleth-openshift.git --follow
```

If you make changes to Java code, you can build and deploy without pushing it to GitHub.

```bash
oc start-build shibboleth-java --from-dir . --follow
```

For anything else, for example the configuration templates, you can simply run the `deploy-shibboleth.bash` again. It will run only a few seconds after the builds are there.

## Clean up

If you want to delete all builds created by this script

```bash
oc delete bc/shibboleth; oc delete is/shibboleth; oc delete bc/shibbboleth-java; oc delete is/shibboleth-java
```

If you want to delete everything else created by this script. In case you used different name, the script will print you the correct command.

```bash
oc delete dc/shibboleth; oc delete route/shibboleth; oc delete service/shibboleth; oc delete secret shibboleth-shibd-conf; oc delete secret shibboleth-apache-conf; oc delete secret shibboleth-apache-html;
```

## Lessons learned

### Request environment variables vs. HTTP headers

There are two ways to pass to authentication information from Apache to your application: *request environment variables* and *HTTP headers*. The Shibboleth documentation favors the first one, but it may not be possible in all programming languages.  With a quick googling it looks like request environment variables work in Java and Python for example, but maybe not in NodeJS. If you decide to use language where only HTTP headers are supported, please make sure you understand its [security implications](https://wiki.shibboleth.net/confluence/display/SHIB2/NativeSPSpoofChecking).

The Apache documentation recommends using *mod_http_proxy* for passing the requests from Apache to our Application, but passing the request environment variables is not possible in *http*, but only using the *mod_ajp_proxy*. Normally we would use the Jetty web server for this kind of small Java services. Unfortunately Jetty 9 has dropped the support for the *AJP* protocol, so we have to use Tomcat instead. This turned out to be lot easier than I remembered: it supports embedded mode and it starts really fast.

### Tomcat request.getAttributeNames()

Although request.getAttribute() returns these attributes, request.getAttributeNames() doesn't list them. 

You can find the longer explanation from the Tomcat issue tracker, but the summary is that the servlet 
spec tests didn't foresee the possibility  of attributes being set internally instead of the 
request.setAttribute() method.

[The example application](src/main/java/fi/csc/chipster/shibboleth/example/ShibbolethServlet.java) demonstrates how to dig out all the attributes from the Tomcat internals, but it may easily break when the Tomcat is updated.		 

The default attribute-map.xml adds a prefix `SHIB_` to all attribute names, so this is how you get e.g. `eppn`:

```java
request.getAttribute("SHIB_eppn");
```
 
### Character encoding

Tomcat assumes the attributes are encoded in ISO-8859-1, although they are in fact UTF-8. There doesn't 
seem to be way to configure this in Tomcat, so fix the encoding in your application.

```java
public static String fixEncoding(String input) throws UnsupportedEncodingException {
	return new String( input.getBytes("ISO-8859-1"), "UTF-8");
}
```

You should request at least the attribute `cn`in the Test Haka, because it's value contains an accented character,
which you can use to test these issues.

