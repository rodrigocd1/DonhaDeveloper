@RestResource(urlMapping='/Documents/*')
global class WebServices 
{
    
     global static HTTPResponse doGet() {
   
        String myCountryCode = '';
      
        List<Document> documents;// = '';//ContractClass.getContractDocuments(myCountryCode);
            
         String body = EncodingUtil.base64Encode(documents[0].Body);

          HttpRequest req = new HttpRequest();
          req.setHeader('Content-Type',documents[0].ContentType);
          req.setMethod('POST');
          req.setEndpoint('http://www.samplerestwebservice.com');
          req.setBody(body);
          req.setTimeout(60000);
         // req.setHeader('Content-Length',String.valueof(documents[0].body.length()));
        
          Http http = new Http();
              return http.send(req);

        }

}