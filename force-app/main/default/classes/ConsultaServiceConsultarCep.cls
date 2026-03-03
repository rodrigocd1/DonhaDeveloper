/*********************************************************************************************************************************************************************

@description Classe de intermediação de solicitação de dados via integração e de deserialize de JSON
@author Rodrigo Donha
@date 10/06/2019
		
**********************************************************************************************************************************************************************/

global class ConsultaServiceConsultarCep 
{
    private static  String metodoGet = 'GET'; 
    
   
    
 	/** 
    @description  método para realização de busca na base de integração por CEP
    @param String cep
    @return Endereco
    @author Rodrigo Donha
    @date 10/06/2019
	*/	
    public static  Endereco buscarEnderecoPorCep( String cep )
    {
        Endereco enderecoResponse = new Endereco(); 
        
        
        String endpoint = ConsultaServiceConsultarCep.gerarURLConsultaPorCEP( cep );                             
        
        String response = ConsultaConnectionConsultarCep.enviarRequest( endpoint , metodoGet );                
            
        enderecoResponse = ( Endereco )JSON.deserialize( response , Endereco.class );        
        
        
        
        return enderecoResponse;
    }
    
    
    
        
 	/** 
    @description  método para realização de busca na base de integração por CEP
    @param String cep
    @return Endereco
    @author Rodrigo Donha
    @date 10/06/2019
	*/	
    public static  String buscarEnderecoPorCepJSON( String cep )
    {

        String endpoint = ConsultaServiceConsultarCep.gerarURLConsultaPorCEP( cep );                             
        
        return ConsultaConnectionConsultarCep.enviarRequest( endpoint , metodoGet );                                    
    }
    
    
    
    /** 
    @description  método para gerarUrl de Endpoint da integração de busca por CEP
    @param String cep
    @return String
    @author Rodrigo Donha
    @date 10/06/2019
	*/	
    private static String gerarURLConsultaPorCEP( String cep )
    {
        return 'https://viacep.com.br/ws/' + cep + '/json/' ;
    }
    
    
    
    global class Endereco
    {
        public String cep 			{ get; set; }
        public String logradouro 	{ get; set; }
        public String complemento 	{ get; set; }
        public String bairro 		{ get; set; }
        public String localidade 	{ get; set; }
        public String uf 			{ get; set; }
        public String unidade 		{ get; set; }
        public String ibge 			{ get; set; }
        public String gia 			{ get; set; }
        
        public Endereco()
        {
            
        }
    }    
}