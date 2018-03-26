#!/bin/bash
# go to the diretory where the script is
cd "$(dirname "$0")"

set -e

keys=()
values=()
defaults=()
descriptions=()

function add_setting {
	keys+=("$1")
	defaults+=("$2")
  descriptions+=("$3")
}

function get_setting {
  for ((i=0;i<${#keys[@]};++i)); do
    if [ "$1" = "${keys[i]}" ]; then
      echo "${values[i]}"
      return
    fi
  done
  echo "Setting \"$1\" not found"
  exit 1    
}

project="$(oc project -q)"
domain="$(oc status | head -n 1 | cut -d ":" -f 2 | tr -d "/")"

# define settings

add_setting name shibboleth "prefix for all the global OpenShift names, e.g. haka"
add_setting cert_dir "~/shibboleth_keys/$project.$domain" "directory for storing the private key and its certificate"
add_setting metadata https://haka.funet.fi/metadata/haka_test_metadata_signed.xml "URL to a xml document describing all the members of the federation, default for Test-Haka"
add_setting metadata_cert https://wiki.eduuni.fi/download/attachments/27297785/haka_testi_2015_sha2.crt "URL to a certificate for checking the authenticity of the metadata, default for Test-Haka"
add_setting discovery_service https://testsp.funet.fi/shibboleth/WAYF "URL to the discover service of the federation, default for Test-Haka"
add_setting attribute_map https://wiki.eduuni.fi/download/attachments/27297794/attribute-map.xml "the default maps all attributes in Test-Haka and production Haka"
add_setting logo /shibboleth-sp/logo.jpg "URL to a logo shown on error pages"
add_setting support your@support.email "support email address of your service, shown on error pages"
add_setting hostname $project.rahti-int-app.csc.fi "the public hostname of the your app"
add_setting path /sso "shibboleth will be configured to use the URL https://<hostname><path>/<name>"

# parse arguments

for key in "$@"; do
  for ((i=0;i<${#keys[@]};++i)); do
    if [ "$1" = "--${keys[i]}" ]; then
      values[i]="$2"; shift 2
      continue
    fi
  done
done


# prompt for missing values
echo ""

for ((i=0;i<${#keys[@]};++i)); do
  if [ -z "${values[i]}" ]; then
    echo "${descriptions[i]}"
    echo "set ${keys[i]} [${defaults[i]}]: 	"
    read value
    if [ -z "$value" ]; then
  	  values[i]="${defaults[i]}"
  	else
  	  values[i]="$value"
  	fi
  fi
done

  
# print settings
# for ((i=0;i<${#keys[@]};++i)); do 
#  echo "${keys[i]}: 	${values[i]}"
# done
# echo ""

name="$(get_setting name)"

# build an image with apache and shibd

# Unfortunately the ´oc´ command doesn't accept the file path directly, but we have 
# pass it from the standard input.

if [[ ! $(oc get bc shibboleth 2> /dev/null) ]]; then
  oc new-build --name shibboleth -D - < dockerfiles/shibboleth/Dockerfile
  sleep 1
  oc logs -f bc/shibboleth
else
  echo "Using existing shibboleth build. Run the following commands to update it later:"
  echo "  bash update_dockerfile.bash shibboleth"
  echo "  oc start-build shibboleth --follow"
  echo ""
fi


# build for the java application

if [[ ! $(oc get bc shibboleth-java 2> /dev/null) ]]; then
  oc new-build https://github.com/chipster/shibboleth-openshift.git -D - < dockerfiles/shibboleth-java/Dockerfile --name shibboleth-java
  sleep 1
  oc logs -f bc/shibboleth-java
else
  echo "Using existing shibboleth-java build. Run the following commands to update it later:"
  echo "  bash update_dockerfile.bash shibboleth-java"
  echo "  oc start-build shibboleth-java --from-dir . --follow"
  echo ""
fi


# deploy application

# Expose the Apache's port 8000 and terminate the TLS on the load balancer. Disable 
# redirects from *http* to *https* by setting ´--insecure-policy=None´, because the 
# same is recommended also in more traditional setups (where TLS is terminated in the Apache). 
# This will use a OpenShift's wildcard TLS certificate. Consider getting a host-specific 
# certificate and terminating the TLS in the Apache instead. I'm not aware of any direct 
# risk associated with this wildcard solution, but your own certificate would be definitely 
# better. 

hostname="$(get_setting hostname)"
path="$(get_setting path)/$name"

if [[ ! $(oc get dc "$name" 2> /dev/null) ]]; then
  oc new-app shibboleth-java --name "$name"
  oc expose dc "$name" --port=80 --target-port 8000
  echo oc create route edge --service "$name" --insecure-policy=None --hostname "$hostname" --path "$path"
  oc create route edge --service "$name" --insecure-policy=None --hostname "$hostname" --path "$path"
fi


# find out the route url

service_url="https://$hostname$path"
entity_id="$service_url"

echo $entity_id
echo ""


# configure apache
mkdir -p tmp

if [[ $(oc get secret "$name"-apache-conf 2> /dev/null) ]]; then
  	oc delete secret "$name"-apache-conf  
fi

if [[ $(oc get secret "$name"-apache-html 2> /dev/null) ]]; then
  	oc delete secret "$name"-apache-html  
fi

cat templates/shibboleth.conf \
  | sed -e "s#{{NAME}}#$name#g" \
	| sed -e "s#{{HOSTNAME}}#$hostname#g" \
  | sed -e "s#{{PATH}}#$path#g" \
  | sed -e "s#{{ENTITY_ID}}#$entity_id#g" \
  | sed -e "s#{{SERVICE_URL}}#$service_url#g" \
  > tmp/shibboleth.conf

cat templates/index.html \
	| sed -e "s#{{NAME}}#$name#g" \
	| sed -e "s#{{HOSTNAME}}#$hostname#g" \
  | sed -e "s#{{PATH}}#$path#g" \
  | sed -e "s#{{ENTITY_ID}}#$entity_id#g" \
  | sed -e "s#{{SERVICE_URL}}#$service_url#g" \
	 > tmp/index.html
  	
oc create secret generic "$name"-apache-conf --from-file=shibboleth.conf=tmp/shibboleth.conf
oc create secret generic "$name"-apache-html --from-file=index.html=tmp/index.html

rm tmp/shibboleth.conf
rm tmp/index.html


# configure shibd

if [[ $(oc get secret "$name"-shibd-conf 2> /dev/null) ]]; then
  	oc delete secret "$name"-shibd-conf  
fi

cat templates/shibboleth2.xml \
	| sed -e "s#{{HOSTNAME}}#$hostname#g" \
  | sed -e "s#{{PATH}}#$path#g" \
  | sed -e "s#{{ENTITY_ID}}#$entity_id#g" \
  | sed -e "s#{{SERVICE_URL}}#$service_url#g" \
  | sed -e "s#{{NAME}}#$name#g" \
  | sed -e "s#{{DISCOVERY_SERVICE}}#$(get_setting discovery_service)#g" \
  | sed -e "s#{{SUPPORT}}#$(get_setting support)#g" \
  | sed -e "s#{{METADATA}}#$(get_setting metadata)#g" \
  | sed -e "s#{{LOGO}}#$(get_setting logo)#g" \
> tmp/shibboleth2.xml

echo ""

# Before your service gets the attributes you requested, those must be mapped. By default 
# only to eduPersonPrincipalName attribute is mapped to "eppn" variable. After loggiing in
# in 'SERVICE_URL/Shibboleth.sso/Login´ you should see your new attributes listed in 
# 'SERVICE_URL/Shibboleth.sso/Session´. The values are hidden, but you will see them in 
# the test application.

curl -s $(get_setting attribute_map) > tmp/attribute-map.xml

# The SAML2 metadata describes all the member SPs and IdPs of the federation. The 
# federation signs it with their own private key and we can check its authenticity 
# with their certificate. Download their certificate.

curl -s $(get_setting metadata_cert) > tmp/metadata.crt

# evaluate the "~" to absolute path
cert_dir="$(eval echo $(get_setting cert_dir))"

if [ ! -d $cert_dir ]; then
  echo ""
  read -p "cert_dir $cert_dir does not exist. Create it and generate new keys [y/N]? " resp
  if [[ "$resp" == "y" ]]; then
    mkdir -p $cert_dir
  else
    echo "ERROR: no cert dir"    
    exit 1
  fi
fi

# We need a private key and its certificate to sign our authentication messages to the 
# IdP and decrypt information we get from it. Luckily a self-signed certificate is enough, 
# so we can simply generate these. We are going to generate the key in the container and 
# then copy it to your laptop.

# Basically you can invent any unique string for it the entityID , but SERVICE_URL is a good 
# choice. We need some place with write permissions to save the keys for a minute. We'll 
# use /tmp now, because there we have write permissions. shib-keygen will try to change the
# owner of the key file, which is not possible with these permissions. We'll have to find out 
# the current uid and groop and pass them to shib-keygen to suppress ugly warnings about this.

# There should be a ´oc cp´ command for copying files, but for some reason it didn't do 
# anything (´oc cp shibboleth:/tmp/sp-cert.pem ~/secure/sp-cert.pem´), so I used ´oc rsh´ 
# instead.

# Store the private key sp-cert.pem in a such place on your computer that you don't 
# accidentally  make it public (for example by pushing it to a code repo). The second file, 
# ´sp-cert.pem´ will be public anyway, but let's keep it in the same directory, because we are 
# going to use them together.

if [ ! -f $cert_dir/sp-key.pem ]; then
  echo "Private key $cert_dir/sp-key.pem does not exist. Generating it"
  pod_user="$(oc rsh dc/"$name" bash -c "id -u" | tr '\r' '\n')"
  pod_group="$(oc rsh dc/"$name" bash -c "id -u" | tr '\r' '\n')"
  oc rsh dc/"$name" shib-keygen -h $hostname -y 3 -e $entity_id -o /tmp -u $pod_user -g $pod_group -f
  oc rsh dc/"$name" cat /tmp/sp-key.pem > $cert_dir/sp-key.pem
  oc rsh dc/"$name" cat /tmp/sp-cert.pem > $cert_dir/sp-cert.pem
  chmod go-rwx $cert_dir/sp-key.pem
  oc rsh dc/"$name" rm /tmp/sp-key.pem
  oc rsh dc/"$name" rm /tmp/sp-cert.pem  
  echo ""
else
  echo "Using existing private key $cert_dir/sp-key.pem"
fi
  	
oc create secret generic "$name"-shibd-conf \
  --from-file=shibboleth2.xml=tmp/shibboleth2.xml \
  --from-file=attribute-map.xml=tmp/attribute-map.xml \
  --from-file=sp-key.pem=$cert_dir/sp-key.pem \
  --from-file=sp-cert.pem=$cert_dir/sp-cert.pem \
  --from-file=metadata.crt=tmp/metadata.crt
  	
rm tmp/shibboleth2.xml
rm tmp/attribute-map.xml
rm tmp/metadata.crt
echo ""

# remove old secret mounts
if oc volume dc/"$name" --name shibd-conf > /dev/null 2>&1; then
	oc set volume dc/"$name" --remove --name shibd-conf
fi
if oc volume dc/"$name" --name apache-conf > /dev/null 2>&1; then
	oc set volume dc/"$name" --remove --name apache-conf
fi
if oc volume dc/"$name" --name apache-html > /dev/null 2>&1; then
	oc set volume dc/"$name" --remove --name apache-html
fi

# mount the secrets
oc set volume dc/"$name" --add -t secret --secret-name "$name"-shibd-conf --mount-path /etc/shibboleth/secret --name shibd-conf
oc set volume dc/"$name" --add -t secret --secret-name "$name"-apache-conf --mount-path /etc/apache2/sites-enabled --name apache-conf
oc set volume dc/"$name" --add -t secret --secret-name "$name"-apache-html --mount-path /var/www/html$path --name apache-html
rm -rf tmp
echo ""

echo "---------------------------------------------------------------------------------------------"
echo "Register the service in Haka resource registry https://rr.funet.fi/rr"
echo ""
echo "** Organiztion information"
echo "Select your organization."
echo ""
echo "** SP Basic Information"
echo "Entity Id                                             $entity_id"
echo "Service Name (Finnish)                                <fill in>"
echo "Service Name (Engilish)                               <fill in for production Haka>"
echo "Service Name (Swedish)                                <fill in for production Haka>"
echo "Service Description (Finnish)                         <fill in for production Haka>"
echo "Service Description (English)                         <fill in for production Haka>"
echo "Service Description (Swedish)                         <fill in for production Haka>"
echo "Service Login Page URL                                <login page for humans, for production Haka>"
echo "Discovery Response URL                                $service_url/Shibboleth.sso/Login"
echo "urn:oasis:names:tc:SAML:2.0:nameid-format:transient   x"
echo "eduGain                                               <e.g. unselected>"
echo "Haka                                                  <e.g. unselected>"
echo "Haka test                                             <e.g. selected>"
echo ""
echo "** SP SAML Endpoints"
echo "URL index #1                                          $service_url/Shibboleth.sso/SAML2/POST"
echo ""
echo "** Certificates"
echo "Copy the contents of the file $(get_setting cert_dir)/sp-cert.pem to the text field (without the first and "
echo "last line)."
echo ""
echo "** Requested Attributes"
echo "The test application uses these two attributes"
echo ""
echo "eduPersonPrincipalName                                x    Technical user identifier"
echo "cn                                                    x    Human-readable name of the user"
echo ""
echo "Select the additional attributes you need and explain why. See"
echo "- https://rr.funet.fi/haka/ (your own information)"
echo "- https://testsp.funet.fi/haka/ (you will get the test credentials after the registration)"
echo "- https://wiki.eduuni.fi/display/CSCHAKA/funetEduPersonSchema2dot2"
echo ""
echo "In Test-Haka, select at least the cn attribute, becuase the test user's name contains an "
echo "accented character, which allows us to test a character encoding issue later."
echo ""
echo "** UI Extensions"
echo "Privacy Policy URL (Finnish)                          <fill in for production Haka>"
echo ""
echo "** Contact Information"
echo "Contact type                                          Technical"
echo "First Name                                            <fill in, e.g. Chipster>"
echo "Last Name                                             <fill in, e.g. Helpdesk>"
echo "E-Mail                                                $(get_setting support)"
echo "Contact type                                          Support"
echo "First Name                                            <fill in for production Haka>"
echo "Last Name                                             <fill in for production Haka>"
echo "E-Mail                                                $(get_setting support)"
echo "--------------------------------------------------------------------------------------------"
echo ""
echo "If you want to delete all builds created by this script"
echo "    oc delete bc/shibboleth; oc delete is/shibboleth; oc delete bc/shibbboleth-java; oc delete is/shibboleth-java"
echo ""
echo "If you want to delete everything else created by this script"
echo "    oc delete dc/$name; oc delete route/$name; oc delete service/$name; oc delete secret $name-shibd-conf; oc delete secret $name-apache-conf; oc delete secret $name-apache-html"
echo ""
echo "$service_url/Shibboleth.sso/Login"
echo "$service_url/Shibboleth.sso/Logout"
echo "$service_url/Shibboleth.sso/Session"
echo "$service_url/secure"
echo ""   
