/*********************************************************************************************************************************************************************

@description Classe de comunicação do salesforce com o webservice desejado
@author Rodrigo Donha
@date 10/06/2019
		
**********************************************************************************************************************************************************************/
public class ConsultaConnectionConsultarCep 
{
	
    /** 
    @description  método para realizar o envio da requisição com os dados para o webservice e retorna o Body como String
    @param String endpoint, String metodo
    @return String
    @author Rodrigo Donha
    @date 10/06/2019
	*/	
    public static String enviarRequest( String endpoint, String metodo )
    {
        String retorno = '';
        
        HttpRequest request = new HttpRequest();
        
        request.setEndpoint( endpoint );
        request.setMethod( metodo );
        
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