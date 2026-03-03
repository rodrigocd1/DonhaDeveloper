/*********************************************************************************************************************************************************************

@description Classe de comunicação do salesforce com o webservice desejado
@author Globant
@date 27/02/2022
		
**********************************************************************************************************************************************************************/
public class AC_ConsultaConnection 
{
	
    /** 
    @description  método para realizar o envio da requisição com os dados para o webservice e retorna o Body como String
    @param String endpoint, Map< String, String > mapHeaders, String metodo
    @return String
    @author Rodrigo Donha
    @date 27/02/2022
	*/	
    public static String enviarRequest( String endpoint, String metodo , Map< String, String > mapHeaders , String body )
    {
        String retorno = '';
        
        HttpRequest request = new HttpRequest();
        
        request.setEndpoint( endpoint );
        request.setMethod( metodo );
        
        for( String chave: mapHeaders.keyset())
        {
          	String valor = mapHeaders.get(chave);
            request.setHeader(chave, valor);
            system.debug(' ===>  Header = ' + chave + ':' + valor );
        }
        
        if( body != '')
        {
        	request.setBody( body );
            system.debug(' ===>  request:' + body );
        }
        
        HttpResponse response = new HttpResponse();
        
        try
        {
            Http http 	= new Http();
            response 	= http.send( request );
            
        	system.debug(' ===>  response:' + response.getBody() );
        
            return response.getBody();
        }
        catch( Exception e )
        {
            retorno = 'Erro: ' + e.getMessage();
        }
        
        return retorno;
    }
    
}