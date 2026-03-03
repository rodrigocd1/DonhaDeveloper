public class PDF_From_Base64
{    
    public Blob img;
            
	public Object getImg() 
    {
    	List<ContentVersion> bodyList = [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId= '0696S00000Yw0GqQAJ'];
		
        // Version Data é o Base64 eu coloquei no SF para não ficar transportando String gigante
    	img = (Blob) bodyList[0].get('VersionData'); 
        
    	return EncodingUtil.base64Encode(img);
	}
        
}