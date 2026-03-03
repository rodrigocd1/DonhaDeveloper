public class AC_LCBotaoCriaProtocoloController {
    
    public String idProtoc {get; set;}
   /* 
    public static AC_Protocolo__c verificarUltimoProtocolo(String idConta){
            AC_Protocolo__c protocolo = [SELECT Id 
                                        FROM AC_Protocolo__c 
                                        WHERE AC_Conta__c =: idConta 
                                        AND SystemModstamp > :Datetime.now().addMinutes(-15) 
                                        ORDER BY CreatedDate DESC LIMIT 1];
            system.debug('ID:'+ protocolo);
            return protocolo;
        }
    */
    @AuraEnabled
    public static Id criaProtocolo(String idConta){
        
        String idProtocol;
        /*
        AC_Protocolo__c protocolo = new AC_Protocolo__c();
        protocolo.Name = 'x';
        protocolo.AC_Conta__c = idConta;
        
        insert protocolo;
        
        idProtocol = protocolo.Id;
        */
        return idProtocol;
    }

    @AuraEnabled
    public static string validarProtocolo(String idProtoc, String protocolo, String idConta){
        try {
           // verificarUltimoProtocolo(idConta);
           
            return idProtoc;
        } catch (Exception e) {
            criaProtocolo(idConta);
            return protocolo;
        }
    }
}