public class TestController 
{
    @AuraEnabled
    public static List< Account > obterContas()
    {
        return [SELECT ID, Name From Account];
    }
    
    @AuraEnabled
    public static List< Account > obterContas( String idConta )
    {
        return [SELECT ID, Name From Account where id =: idConta];
    }
    

}