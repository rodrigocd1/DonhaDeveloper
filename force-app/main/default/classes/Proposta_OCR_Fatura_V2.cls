/**
 * @name: Proposta_OCR_Fatura_V2
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:31
 * @description: Proposta_OCR_Fatura_V2 class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

global class Proposta_OCR_Fatura_V2 {

    @TestVisible public static String  environment       = (EnvironmentUtils.getRaw() != null) ? EnvironmentUtils.getRaw() : 'sandbox';
    @TestVisible public static String  logLevelDefault   = (EnvironmentUtils.getLogLevel() != null) ? EnvironmentUtils.getLogLevel() : 'INFO';
    @TestVisible public static Integer maxDebugLength    = (EnvironmentUtils.getMaxDebugLength() != null ) ? (Integer)EnvironmentUtils.getMaxDebugLength() : 3000;

	 global static infoOCR enviar_requisicao_http(String json_string, String endpoint) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type','application/json');
        req.setHeader('Access_token', Label.BEARER_LEITOR_FATURA_PRODUCTION);
        req.setBody(json_string);
        req.setTimeout(120000);
        HttpResponse res =  http.send(req);
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return (infoOCR) JSON.deserialize(res.getBody(), infoOCR.class);
        } 
         else {
         	 infoOCR errorResponse = new infoOCR();
          	 errorResponse.errorMessage =  res.getBody();
             return errorResponse;
        }
    }
   
    global static String make_json(string doc_link, string distribuidora) {
        Map<string, string> map_json = new Map<string, string>();
        map_json.put('url_fatura', doc_link);
        map_json.put('distribuidora', distribuidora);
        String jsonBody = JSON.serializePretty(map_json);
        return jsonBody;
    }
    global static infoOCR ler_fatura(string doc_link, string distribuidora) {
        String json_string =  make_json(doc_link, distribuidora);
        String endpoint = LAbel.ENDPOINT_LEITOR_FATURA_PRODUCTION;
        infoOCR response = enviar_requisicao_http(json_string, endpoint);
        return response;
       
    }
     global class infoOCR {
        @InvocableVariable
        global String numero_do_cliente;
        @InvocableVariable
        global String numero_da_instalacao;
        @InvocableVariable
        global String Titular;
        @InvocableVariable
        global String cpf_cnpj;
        @InvocableVariable
        global String grupo_tarifario;
        @InvocableVariable
        global String padrao_da_rede;
        @InvocableVariable
        global String data_de_vencimento;
        @InvocableVariable
        global String data_da_leitura_atual;
        @InvocableVariable
        global String data_da_leitura_anterior;
        @InvocableVariable
        global String data_da_proxima_leitura;
        @InvocableVariable
        global String mes_de_referencia;
        @InvocableVariable
        global String numero;
        @InvocableVariable
        global String logradouro;
        @InvocableVariable
        global String complemento;
        @InvocableVariable
        global String bairro;
        @InvocableVariable
        global String cidade;
        @InvocableVariable
        global String uf;
        @InvocableVariable
        global String cep;
        @InvocableVariable
        global String usina_da_fatura;
        @InvocableVariable
        global String subclasse;
        @InvocableVariable
        global Double cip;
        @InvocableVariable
        global integer kwh_medio;
        @InvocableVariable
        global integer kwh_saldo;
        @InvocableVariable
        global double kwh_consumo_01;
        @InvocableVariable
        global double kwh_consumo_02;
        @InvocableVariable
        global double kwh_consumo_03;
        @InvocableVariable
        global double kwh_consumo_04;
        @InvocableVariable
        global double kwh_consumo_05;
        @InvocableVariable
        global double kwh_consumo_06;
        @InvocableVariable
        global double kwh_consumo_07;
        @InvocableVariable
        global double kwh_consumo_08;
        @InvocableVariable
        global double kwh_consumo_09;
        @InvocableVariable
        global double kwh_consumo_10;
        @InvocableVariable
        global double kwh_consumo_11;
        @InvocableVariable
        global double kwh_consumo_12;
        @InvocableVariable
        global double kwh_consumo_13;
        @InvocableVariable
        global double kwh_energia_compensada;
        @InvocableVariable
        global double kwh_energia_compensada_te;
        @InvocableVariable
        global double kwh_energia_compensada_tusd;
        
        @InvocableVariable
        global double kwh_energia_injetada;
        @InvocableVariable
        global double kwh_energia_injetada_te;
        @InvocableVariable
        global double kwh_energia_injetada_tusd;
        
        @InvocableVariable
        global double kwh_energia_nao_compensada;
        @InvocableVariable
        global double kwh_energia_nao_compensada_te;
        @InvocableVariable
        global double kwh_energia_nao_compensada_te_tusd;
         
        global double valor_energia_compensada;
        @InvocableVariable
        global double valor_energia_compensada_te;
        @InvocableVariable
        global double valor_energia_compensada_tusd;
        
        @InvocableVariable
        global double valor_energia_injetada;
        @InvocableVariable
        global double valor_energia_injetada_te;
        @InvocableVariable
        global double valor_energia_injetada_tusd;
        
        @InvocableVariable
        global double valor_energia_nao_compensada;
        @InvocableVariable
        global double valor_energia_nao_compensada_te;
        @InvocableVariable
        global double valor_energia_nao_compensada_te_tusd;
         
        global double tarifa_energia_compensada;
        @InvocableVariable
        global double tarifa_energia_compensada_te;
        @InvocableVariable
        global double tarifa_energia_compensada_tusd;
        
        @InvocableVariable
        global double tarifa_energia_injetada;
        @InvocableVariable
        global double tarifa_energia_injetada_te;
        @InvocableVariable
        global double tarifa_energia_injetada_tusd;
        
        @InvocableVariable
        global double tarifa_energia_nao_compensada;
        @InvocableVariable
        global double tarifa_energia_nao_compensada_te;
        @InvocableVariable
        global double tarifa_energia_nao_compensada_te_tusd;
        
        @InvocableVariable
        global double valor_a_pagar;
         
        global boolean aviso_de_corte;
        @InvocableVariable
        global String classe;
        @InvocableVariable
        global boolean baixa_renda;
        @InvocableVariable
        global string distribuidora_nome;
        @InvocableVariable
        global string icms;
        @InvocableVariable
        global string pis;
        @InvocableVariable
        global double cofins;
        @InvocableVariable
        global double Responsavel_pela_extracao;
        @InvocableVariable
        global string errorMessage;
         
        //Futura exclusão
        @InvocableVariable
        global double consumo_kwh_01;
        @InvocableVariable
        global double consumo_kwh_02;
        @InvocableVariable
        global double consumo_kwh_03;
        @InvocableVariable
        global double consumo_kwh_04;
        @InvocableVariable
        global double consumo_kwh_05;
        @InvocableVariable
        global double consumo_kwh_06;
        @InvocableVariable
        global double consumo_kwh_07;
        @InvocableVariable
        global double consumo_kwh_08;
        @InvocableVariable
        global double consumo_kwh_09;
        @InvocableVariable
        global double consumo_kwh_10;
        @InvocableVariable
        global double consumo_kwh_11;
        @InvocableVariable
        global double consumo_kwh_12;
        @InvocableVariable
        global double consumo_kwh_13;
        @InvocableVariable
        global double consumo_medio_kwh;
        @InvocableVariable
        global string estado;
        @InvocableVariable
        global string nome;
        @InvocableVariable
        global string leitura_atual_dt;
        @InvocableVariable
        global string numero_cliente;
        @InvocableVariable
        global string numero_uc;
        @InvocableVariable
        global string vencimento_da_fatura_dt;
        
     }
    global Class Inputs
    {
        @InvocableVariable (label='doc_link' description='doc_link' required=true)
        global String doc_link;
         @InvocableVariable (label='distribuidora' description='distribuidora')
        global String distribuidora;
    }
    @InvocableMethod
    global static List<infoOCR> execute (List<Proposta_OCR_Fatura_V2.Inputs> input_list)
    {
         list<infoOCR> res_list = new list<infoOCR>();
        for (Proposta_OCR_Fatura_V2.Inputs one_input: input_list) {
           infoOCR res = Proposta_OCR_Fatura_V2.ler_fatura(one_input.doc_link, one_input.distribuidora);
           res_list.add(res);
        }
        system.debug(res_list);
        return res_list;
        
        
    }
}