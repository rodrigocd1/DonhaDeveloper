@JsonAccess(serializable='always')
global with sharing class CKBR_CTL_ProductShowCase {

    global static final String CKBR_CONSTANT_TIPO_CATEGORIA = 'R';
    global static final String microserviceMatrixKeyVitrine = 'sinv-vitrine';

    global class CustomException extends Exception {}

    global class FeatureManager { 
        @AuraEnabled
        public String featureName;
        @AuraEnabled
        public Boolean isActive;
        @AuraEnabled
        public String featureDisabledMessage;
    }

    @AuraEnabled
    public static FeatureManager getFeatureManager(String featureApiName) {
        FeatureManager featureManager = new FeatureManager();

        // CKBR_CMT_GerenciadorFuncionalidade__mdt feature = [
        //     SELECT CKBR_CMT_TXT_Label__c, CKBR_CMT_CKB_Active__c, CKBR_CMT_TXT_FeatureDisabledMessage__c
        //     FROM CKBR_CMT_GerenciadorFuncionalidade__mdt
        //     WHERE CKBR_CMT_TXT_FunctionalAPI__c = :featureApiName
        //     LIMIT 1
        // ];

        featureManager.featureName = '';
        featureManager.isActive = true;
        featureManager.featureDisabledMessage = '';

        return featureManager;
    }

    // public Object call(String action, Map<String, Object> args) {
    //     Map<String, Object> input = (Map<String, Object>) args.get('input');
    //     Map<String, Object> output = (Map<String, Object>) args.get('output');
    //     Map<String, Object> options = (Map<String, Object>) args.get('options');
    //     return invokeMethod(action, input, output, options);
    // }

    // global Object invokeMethod(
    //     String action,
    //     Map<String, Object> input,
    //     Map<String, Object> output,
    //     Map<String, Object> options
    // ) {
    //     getParameters(input, options); 

    //     Map<String, Object> mapReturnedData = callVitrineCalloutData(microserviceMatrixKeyVitrine, options);

    //     output.put('result', mapReturnedData);
    //     return output;
    // }

    // global void getParameters(Map<String, Object> input, Map<String, Object> options) {  
    //     String idRegistro = (String) input.get('aRecordId'); // Corrigido para evitar erros de casting
    //     System.debug('aRecordId' + idRegistro);    
    //     if (idRegistro != null) {
    //         FinancialAccount fcc = [
    //             SELECT
    //                 Id,
    //                 FinancialAccountNumber,
    //                 CKBR_FAC_TXT_Agency__c  
    //             FROM FinancialAccount
    //             WHERE Id = :idRegistro 
    //             LIMIT 1
    //         ]; 

    //         // Certifique-se de usar o objeto retornado conforme necessário
    //         options.put('financialAccount', fcc); 
    //         System.debug('options >>> FinancialAccount' + fcc); 
    //     }
    // }

    // global static Map<String, Object> callVitrineCalloutData(String aMicroserviceMatrixKeyVitrine, Map<String, Object> options) {
    //     Map<String, Object> response = new Map<String, Object>();
    //     try {
    //         System.debug('aMicroserviceMatrixKeyVitrine >>> test' + aMicroserviceMatrixKeyVitrine);
    //         System.debug('options >>> test' + JSON.serialize(options));

    //         FinancialAccount financialAccount = (FinancialAccount) options.get('financialAccount');

    //         Map<String, Object> mapHeadersVitrine = new Map<String, Object>{
    //             'agencia' => financialAccount.CKBR_FAC_TXT_Agency__c,
    //             'conta' => financialAccount.FinancialAccountNumber, 
    //             'tipoCategoria' => CKBR_CONSTANT_TIPO_CATEGORIA
    //         }; 

    //         System.debug('financialAccount >>> test' + financialAccount);   

    //         Map<String, Object> mapReturnedData = CKBR_CalloutMicroservices.sendRequest(null, mapHeadersVitrine, microserviceMatrixKeyVitrine);

    //         System.debug('mapReturnedData >>> dados ' + mapReturnedData);

    //         if (mapReturnedData.containsKey('data')) {
    //             response.put('data', mapReturnedData);
    //         }

    //     } catch (Exception ex) {
    //         throw new CustomException('Error Class ' + ex.getMessage());
    //     } 
    //     return response;
    // }
}