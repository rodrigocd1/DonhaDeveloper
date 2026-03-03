global class AC_ConsultaHistoricoFinanceiro
{        
    
    /** 
    @description  método para Obter Access token
    @param none
    @return DetalheTitulo
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    public static String obterAccessToken()
    {        
		Token token = new Token();                
        
        Map< String , String > mapHeaders = AC_ConsultaHistoricoFinanceiro.obterHeadersToken();
        
        String body = obterBodytoken();
                
        String endpoint = AC_ConsultaHistoricoFinanceiro.gerarURLToken();
        
        String response = AC_ConsultaConnection.enviarRequest( endpoint , 'POST' , mapHeaders  , body );                
            
        token = ( Token )JSON.deserialize( response , Token.class );                        
        
        return token.access_token;
        
    }
	


  /** 
    @description  método para realização de busca de titulos na Base
    @param String codCad
    @return DetalheTitulo
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    public static  ListaTituloFinanceiro buscarListaTitulosFinanceiros( String codCad )
    {
        ListaTituloFinanceiro ListaTitulosFinanceirosResponse = new ListaTituloFinanceiro(); 
        
        String  token = obterAccessToken();
        
        Map< String , String > mapHeaders = AC_ConsultaHistoricoFinanceiro.obterHeadersDetalheTitulo( token );
        
        String body = '';
                
        String endpoint = AC_ConsultaHistoricoFinanceiro.gerarURLListaTitulos( codCad );                             		        
        
        String response = AC_ConsultaConnection.enviarRequest( endpoint , 'GET' , mapHeaders  , body );                
            
        ListaTitulosFinanceirosResponse = ( ListaTituloFinanceiro )JSON.deserialize( response , ListaTituloFinanceiro.class );                        
        
        return ListaTitulosFinanceirosResponse;
    }    

    
    
    /** 
    @description  método para realização de busca de titulo na Base
    @param String cep
    @return DetalheTitulo
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    public static  DetalheTituloFinanceiro buscarDetalheTituloFinanceiro( String titulo )
    {
        DetalheTituloFinanceiro DetalheFinanceiroResponse = new DetalheTituloFinanceiro(); 
        
        String  token = obterAccessToken();
        
        Map< String , String > mapHeaders = AC_ConsultaHistoricoFinanceiro.obterHeadersDetalheTitulo( token );
        
        String body = '';
                
        String endpoint = AC_ConsultaHistoricoFinanceiro.gerarURLDetalheTitulo( titulo );                             		        
        
        String response = AC_ConsultaConnection.enviarRequest( endpoint , 'GET' , mapHeaders  , body );                
            
        DetalheFinanceiroResponse = ( DetalheTituloFinanceiro )JSON.deserialize( response , DetalheTituloFinanceiro.class );                        
        
        return DetalheFinanceiroResponse;
    }
    /** 
    @description  método para gerarUrl de Endpoint da integração 
    @param String cep
    @return String
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    private static String gerarURLToken( )
    {
        return 'https://apialltech.allcare.com.br/vTeste/api/token'  ;
    }
    
    
    /** 
    @description  método gerar Headers
    @param none
    @return String
    @author Rodrigo Donha
    @date 27/02/2202
	*/	
    private static Map< String , String > obterHeadersToken()
    {
        Map< String , String > mapHeaders = new Map< String , String >();
        mapHeaders.put('Content-Type', 'application/x-www-form-urlencoded');
        mapHeaders.put( 'grant_type'  	, 'password');
        mapHeaders.put( 'username'  	, '8.102' 	);
        mapHeaders.put( 'password'  	, 'All1234' );
        
        return mapHeaders;
    }
    
    
    
    
    /** 
    @description  método gerar Headers
    @param none
    @return String
    @author Rodrigo Donha
    @date 27/02/2202
	*/	
    private static String obterBodytoken()
    {    	
        String body = '';
        
        body += 'grant_type='	+ EncodingUtil.urlEncode('password'	,'UTF-8') + '&'; 
        body += 'username='		+ EncodingUtil.urlEncode('8.102'	,'UTF-8') + '&';   	
        body += 'password='		+ EncodingUtil.urlEncode('All1234'	,'UTF-8');   
        
        return body;
    }
    
    
    
   
    
    

    
    
    
    /** 
    @description  método para gerarUrl de Endpoint da integração 
    @param String cep
    @return String
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    private static String gerarURLListaTitulos( String codCad )
    {
        return 'https://apialltech.allcare.com.br/vTeste/api/genericapi/titulo?CodCad=' + codCad  ;
    }
    
    
    
    /** 
    @description  método para gerarUrl de Endpoint da integração 
    @param String cep
    @return String
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    private static String gerarURLDetalheTitulo( String titulo )
    {
        return 'https://apialltech.allcare.com.br/vTeste/api/genericapi/titulo/' + titulo  ;
    }
    
    
    
    /** 
    @description  método para gerarUrl de Endpoint da integração 
    @param String cep
    @return String
    @author Rodrigo Donha
    @date 27/02/2202
	*/	
    private static Map< String , String > obterHeadersDetalheTitulo( String access_token )
    {
        Map< String , String > mapHeaders = new Map< String , String >();
        
        mapHeaders.put( 'Authorization'  , 'Bearer ' + access_token );
        
        return mapHeaders;
    }
    
    
    global class Token
    {
        String 		access_token;
        String		token_type;
        String		expires_in;
        
        public Token()
        {
            
        }
    }
    
    global class ListaTituloFinanceiro
    {
        @AuraEnabled public ReturnApi 						ReturnApi			{get;set;}
        @AuraEnabled public ReturnRequisicaoListaTitulos	ReturnRequisicao	{get;set;}
        @AuraEnabled public Versao							Versao				{get;set;}
        
        public ListaTituloFinanceiro()
        {
            
        }
    }
    
    
    global class DetalheTituloFinanceiro
    {
        ReturnApi 			ReturnApi			{get;set;}
        ReturnRequisicao	ReturnRequisicao	{get;set;}
        Versao				Versao				{get;set;}
        
        public DetalheTituloFinanceiro()
        {
            
        }
    }
    
    
    global class ReturnApi
    {	
        @AuraEnabled public String Retorno			{get;set;}
        @AuraEnabled public String Erro				{get;set;}
        @AuraEnabled public String MensagemRetorno	{get;set;}
        
        public ReturnApi()
        {
            
        }
    }
    
    global class ReturnRequisicao
    {
        @AuraEnabled public String CodCad			{get;set;}
        @AuraEnabled public String NomeCad			{get;set;}
        @AuraEnabled public String IdTitulo			{get;set;}
        @AuraEnabled public String NumTitulo		{get;set;}
        @AuraEnabled public String DtEmissaoTitulo	{get;set;}
        @AuraEnabled public String CompTitulo		{get;set;}
        @AuraEnabled public String VencTitulo		{get;set;}
        @AuraEnabled public String VlrTitulo		{get;set;}
        @AuraEnabled public String VlrPagoTitulo	{get;set;}
        @AuraEnabled public String SituacaiTitulo	{get;set;}
        
        List< DetalheTitulo > DetalheTitulo 		{get;set;}
        
        public ReturnRequisicao()
        {
            
        }
        
       
    }
    
    
    global class ReturnRequisicaoListaTitulos
    {
        @AuraEnabled public String CodCad			{get;set;}
        @AuraEnabled public String NomeCad			{get;set;}
        
        List< Titulo > Titulos 	;
        
        global ReturnRequisicaoListaTitulos()
        {
            
        }
        
       
    }
    
    public class Titulo
    {
        @AuraEnabled public String IdTitulo			{get;set;}
        @AuraEnabled public String NumTitulo		{get;set;}
        @AuraEnabled public String CompTitulo		{get;set;}             
        @AuraEnabled public String VencTitulo		{get;set;}
        @AuraEnabled public String VlrTitulo		{get;set;}
        @AuraEnabled public String SituacaiTitulo	{get;set;}
        
        public Titulo()
        {
            
        }
    }
    
    
     public class DetalheTitulo
     {
         @AuraEnabled public String CodCad				{get;set;}
         @AuraEnabled public String NomeBenef			{get;set;}
         @AuraEnabled public String GrauDepBenefTitulo	{get;set;}
         @AuraEnabled public String DescBenefTitulo		{get;set;}
         @AuraEnabled public String VlrBenefTitulo		{get;set;}
         
         public DetalheTitulo()
         {
             
         }
             
     }
    
	global class Versao
    {
        @AuraEnabled public String VersaoSistema 					 {get;set;}
        @AuraEnabled public String VersaoDataType					 {get;set;}
        @AuraEnabled public String DataType							 {get;set;}
        
        public Versao()
        {
            
        }
        
    }
	
/*
 * TOKEN
 * {
    "access_token": "EmxdJK3PaKfkM7dW3lpFgP4MYdVt6-8YvuKHes-iRL41pr_O0sWlnrRuNaFicec2ymkN_8lxj1wgpanQzmV8E-RZViNdjTTZGSlml1hfOsJ8zA0c9j2XpS8o4HS2hxLYnc40tIZkGUXZt2P4AGPkAWn26m8cmtOwlfyovNcNcjlcF34j1cNaxnnWEisHpusxmUtZJPpVMGUImxgaNm_CW7YKdWDNwH3B_wFF7iW8frVkKRKcMgVUxOwMBj9xODJodPxO29eiJ-kz4yi4P_wOKuqSgn7h7vJRYw0uBlJNy2QMZKATbru2Pbs6yCWGBwz6AEm0AA_604RnlqgASVQ4xxKwU3StmxC08DFoW-DmnHDreVw4nXRRB8BblvlD971q",
    "token_type": "bearer",
    "expires_in": 10367999
}
*
*
TITULO
 * 
 * {
    "ReturnApi": {
        "Retorno": true,
        "Erro": false,
        "MensagemRetorno": "Requisição efetuada com sucesso."
    },
    "ReturnRequisicao": {
        "CodCad": 600700,
        "NomeCad": "Albert Einstein",
        "Titulos": [
            {
                "IdTitulo": 100.0,
                "NumTitulo": 500100200,
                "CompTitulo": "2022-01-01T00:00:00",
                "VencTitulo": "2022-01-10T00:00:00",
                "VlrTitulo": 120.25,
                "SituacaiTitulo": "Pago"
            },
            {
                "IdTitulo": 101.0,
                "NumTitulo": 500100201,
                "CompTitulo": "2022-02-01T00:00:00",
                "VencTitulo": "2022-02-10T00:00:00",
                "VlrTitulo": 120.25,
                "SituacaiTitulo": "Pago"
            },
            {
                "IdTitulo": 102.0,
                "NumTitulo": 500100202,
                "CompTitulo": "2022-03-01T00:00:00",
                "VencTitulo": "2022-03-10T00:00:00",
                "VlrTitulo": 120.25,
                "SituacaiTitulo": "Em Aberto"
            },
            {
                "IdTitulo": 103.0,
                "NumTitulo": 500100203,
                "CompTitulo": "2022-04-01T00:00:00",
                "VencTitulo": "2022-04-10T00:00:00",
                "VlrTitulo": 120.25,
                "SituacaiTitulo": "Em Aberto"
            }
        ]
    },
    "Versao": {
        "VersaoSistema": "4.0.0.0",
        "VersaoDataType": "3.0.0.15",
        "DataType": "AllTech.Type.ReturnWebService"
    }
}
  
 * 
 * DETALHE
{
    "ReturnApi": {
        "Retorno": true,
        "Erro": false,
        "MensagemRetorno": "Requisição efetuada com sucesso."
    },
    "ReturnRequisicao": {
        "CodCad": 600700,
        "NomeCad": "Albert Einstein",
        "IdTitulo": 100.0,
        "NumTitulo": 500100201,
        "DtEmissaoTitulo": "2022-12-26T00:00:00",
        "CompTitulo": "2022-02-01T00:00:00",
        "VencTitulo": "2022-02-10T00:00:00",
        "VlrTitulo": 120.25,
        "VlrPagoTitulo": 122.4,
        "SituacaiTitulo": "Pago",
        "DetalheTitulo": [
            {
                "CodCad": 600700,
                "NomeBenef": "Albert Einstein",
                "GrauDepBenefTitulo": "Titular",
                "DescBenefTitulo": "Plano Médico",
                "VlrBenefTitulo": 50.0
            },
            {
                "CodCad": 600701,
                "NomeBenef": "Maria Madalena",
                "GrauDepBenefTitulo": "Esposa(o)",
                "DescBenefTitulo": "Plano Médico",
                "VlrBenefTitulo": 50.0
            },
            {
                "CodCad": 600702,
                "NomeBenef": "Albert Einstein Jr",
                "GrauDepBenefTitulo": "Filho(a)",
                "DescBenefTitulo": "Plano Médico",
                "VlrBenefTitulo": 20.25
            }
        ]
    },
    "Versao": {
        "VersaoSistema": "4.0.0.0",
        "VersaoDataType": "3.0.0.15",
        "DataType": "AllTech.Type.ReturnWebService"
    }*/
   
}