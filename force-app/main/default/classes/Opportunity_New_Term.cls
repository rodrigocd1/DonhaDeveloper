/**
 * @name: Opportunity_New_Term
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:31
 * @description: Opportunity_New_Term class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

global without sharing class Opportunity_New_Term {

  @TestVisible public static String  environment       = (EnvironmentUtils.getRaw() != null) ? EnvironmentUtils.getRaw() : 'sandbox';
  @TestVisible public static String  logLevelDefault   = (EnvironmentUtils.getLogLevel() != null) ? EnvironmentUtils.getLogLevel() : 'INFO';
  @TestVisible public static Integer maxDebugLength    = (EnvironmentUtils.getMaxDebugLength() != null ) ? (Integer)EnvironmentUtils.getMaxDebugLength() : 3000;
      
     global class newTermGerador {
       @InvocableVariable
       global String errorMessage;
    }

    global Class Inputs
    {   
        @InvocableVariable (label='opp_id' description='ID da Oportunidade' required=true) 
        global String opp_id;

        @InvocableVariable(label='auths (default = whatsapp)' description='Tipo de autenticação para realizar assinatura.Opções: email, sms, whatsapp, pix, api, icp_brasil. Nos campos adicionais selfie_enabled, handwritten_enabled, official_document_enabled, liveness_enabled, facial_biometrics_enabled, devem ser obrigatoriamente igual a false quando auths for igual a icp_brasil. Só é permitido enviar uma das opções.')
        global String auths = 'whatsapp';

        @InvocableVariable(label='has_documentation (default = true)' description='Não solicita os campos CPF e data de nascimento do signatário no momento da assinatura. Útil para signatários que não possuem CPF. Se for false, não é possível enviar os campos documentation e birthday. Quando o auths escolhido é icp_brasil ou pix, deve estar igual a true.')
        global Boolean has_documentation = true;

        @InvocableVariable(label='delivery (default = email)' description='Informa como o signatário receberá as notificações de confirmação de assinatura e de documento finalizado. Se a opção for none, o signatário não receberá essas notificações. Opções disponíveis email e none.')
        global String delivery = 'email';

        @InvocableVariable(label='selfie_enabled (default = false)' description='Define a solicitação de selfie como ponto de autenticação ao signatário no momento da assinatura, utilizando a câmera do dispositivo. Algumas incompatibilidades podem ocorrer como: caso o navegador não tenha suporte ao plugin; dispositivo não possua câmera instalada corretamente ou usuário tenha bloqueado acesso à câmera.')
        global Boolean selfie_enabled = false;

        @InvocableVariable(label='handwritten_enabled (default = false)' description='Define a solicitação de assinatura manuscrita como ponto de autenticação no momento da assinatura.')
        global Boolean handwritten_enabled = false;

        @InvocableVariable(label='official_document_enabled (default = false)' description='Define a solicitação da foto (frente e verso) do documento oficial como ponto de autenticação do signatário no momento da assinatura.')
        global Boolean official_document_enabled = false;

        @InvocableVariable(label='liveness_enabled (default = false)' description='Define a solicitação de selfie dinâmica como ponto de autenticação adicional para o signatário.')
        global Boolean liveness_enabled = false;
        
        @InvocableVariable(label='communicate_by (default = email)' description='Informa como o signatário receberá a solicitação de assinatura e a informação de cancelamento do processo de assinatura. O envio dessas notificações possui um custo adicional (por documento) e demanda uma configuração específica na conta.')
        global String communicate_by = 'email';
        
        @InvocableVariable(label='facial_biometrics_enabled (default = false)' description='Define a solicitação de biometria facial como ponto de autenticação adicional para o signatário. Não é permitido usar assinatura com biometria facial em conjunto ao Widget Embedded nesta versão. Os campos official_document_enabled, liveness_enabled, devem ser obrigatoriamente igual a false quando facial_biometrics_enabled for igual a true.')
        global Boolean facial_biometrics_enabled = false;
        
    }

    @InvocableMethod
    global static list<newTermGerador> execute (List<Opportunity_New_Term.Inputs> input_list)
    {        
        list<newTermGerador> res_list = new list<newTermGerador>();
 
        String endpoint = Label.ENDPOINT_OPPORTUNITY_NEW_TERM + input_list[0].opp_id ;
        
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Access_token', 'Bearer 465a17ab-8a57-40fd-a1da-1344b976c80c');

        Map<string, Object> map_json = new Map<string, Object>();
        Map_json.put('facial_biometrics_enabled', (Boolean)input_list[0].facial_biometrics_enabled);
        Map_json.put('communicate_by', (String)input_list[0].communicate_by);
        map_json.put('liveness_enabled', (Boolean)input_list[0].liveness_enabled);
        map_json.put('official_document_enabled', (Boolean)input_list[0].official_document_enabled);
        map_json.put('handwritten_enabled', (Boolean)input_list[0].handwritten_enabled);
        Map_json.put('selfie_enabled', (Boolean)input_list[0].selfie_enabled);
        Map_json.put('delivery', (String)input_list[0].delivery);
        Map_json.put('has_documentation', (Boolean)input_list[0].has_documentation);
        Map_json.put('auths', (String)input_list[0].auths);
        Map_json.put('opp_id', (String)input_list[0].opp_id);
        //req.setBodyAsBlob(Blob.valueOf(JSON.serializePretty(map_json)));
        req.setTimeout(120000);
        HttpResponse res =  http.send(req);
        if (res.getStatusCode() == 200) {
          return res_list;
        }
        else {
         	 newTermGerador errorResponse = new newTermGerador();
          	 errorResponse.errorMessage =  res.getBody();
             res_list.add(errorResponse);
             return res_list;
        }
    }
}