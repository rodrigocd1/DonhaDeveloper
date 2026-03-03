/*********************************************************************************************************************************************************************

@description Classe de comunicação do salesforce com o webservice desejado
@author Rodrigo Donha
@date 19/06/2024
		
**********************************************************************************************************************************************************************/
public class CKBR_Connection 
{
	
    /** 
    @description  método para realizar o envio da requisição com os dados para o webservice e retorna o Body como String
    @param String endpoint, String metodo
    @return String
    @author Rodrigo Donha
    @date 19/06/2024
	*/	
    public static String enviarRequest( String endpoint, String body, String metodo , Map< String , String > mapParametrosHeader ,  Map< String , String > mapParametrosUrl )
    {
        String retorno = '';
        
        HttpRequest request = new HttpRequest();
        
        endpoint = limparVazio( endpoint );
        body 	 = limparVazio( body );
        metodo   = limparVazio( metodo );
        
        endpoint = inserirParametrosUrl( endpoint , mapParametrosUrl ); 
        
        request = inserirHeaders( request, mapParametrosHeader );
        request.setEndpoint( 	endpoint 	);
        request.setBody( 		body 		);
        request.setMethod( 		metodo 		);
        
        HttpResponse response = new HttpResponse();
        
        try
        {
            Http http 	= new Http();
            response 	= http.send( request );  system.debug(' ===>  response:' + response.getBody() );
            return response.getBody();
        }
        catch( Exception e )
        {
            retorno = 'Erro: ' + e.getMessage();
        }        
        return retorno;
    }
    
    
    
    
    private static String inserirParametrosUrl( String endpoint , Map< String , String > mapParametros )
    {
        for( String key: mapParametros.keyset() )
        {
            String value = mapParametros.get( key );
            
            endpoint += '&' + key + '= ' + value;
        }
        
        return endpoint;
    }
    
    
    
    private static String limparVazio( String value )
    {
        if( String.IsNotBlank( value ) && String.IsNotEmpty( value ) )
        {
             return value;
        }
       
         return '';
    }
    
    
    
    private static HttpRequest inserirHeaders( HttpRequest request , Map< String , String > mapParametros  )
    {
        for( String key: mapParametros.keyset() )
        {
            String value = mapParametros.get( key );           
            request.setheader( key, value );
        }
        return request;
    }
    
    
}