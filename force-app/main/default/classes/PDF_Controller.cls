public class PDF_Controller {
    
    // como chamar a pagina de pdf de exemplo 
    // https://sfdonha-dev-ed--c.visualforce.com/apex/PDF_Exemplo?core.apexpages.request.devconsole=1?&id=001i000001xy4hjAAA
    
    public static  blob content{get;set;}
    
    private final Account acct;
    
    public PDF_Controller(ApexPages.StandardController stdController) 
    {
        this.acct = (Account)stdController.getRecord();
        PDF_Controller.documento('','xxx');
    }
    
    //PDF_Controller.documento('001i000001xy4hjAAA','PDFTeste');
    
    public static Document documento(String idls,String nombre)
    {
        //PageReference pref = page.PDF_Exemplo;
        //pref.getParameters().put('id',idls);
        //pref.setRedirect(true);
       
        
            
        ContentVersion arquivo = [SELECT Id, VersionData FROM ContentVersion WHERE ContentDocumentId = '0696S00000Yw0GqQAJ'];// Id do Arquivo anexado        
        
        Blob base64 = arquivo.VersionData;
         
        content =   EncodingUtil.base64Decode( base64.toString() );
        
        //content = Test.isRunningTest() ? Blob.valueOf('testblob') :  pref.getContent();                                      
        
        
        
        
        Document doc = new Document();
        doc.ContentType ='application/pdf';
        doc.Name = Test.isRunningTest() ? 'nombrepdf' : nombre;
        doc.Body = content;
        doc.FolderId = UserInfo.getUserId();//Test.isRunningTest() ? UserInfo.getUserId(): COL_IdentificadoresRegistros__c.getInstance().CarpetaPDF__C;
        
        //insert doc;
        system.debug('===> id: ' + doc.id);
        
        return doc;
        
    }
}