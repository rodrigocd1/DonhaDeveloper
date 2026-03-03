public class GetUserIP {
    
public static String GetUserIPAddress() {

string ReturnValue = '';

ReturnValue = ApexPages.currentPage().getHeaders().get('True-Client-IP');

if (ReturnValue == '') {

ReturnValue = ApexPages.currentPage().getHeaders().get('X-Salesforce-SIP');

} // get IP address when no caching (sandbox, dev, secure urls)

system.debug('USER IP ADDRESS: ' + ReturnValue);

return ReturnValue;

}
}