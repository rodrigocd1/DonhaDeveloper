/**************************************************************************
   Desenvolvido por: Felipe Augusto da Silva;
   Data de Criação: 04/10/2013;
   Funcionalidade: Componente Oz que auxilia na requisição de uma integração.
**************************************************************************/
global class OzIntegracaoRequest {



	/** Utilizado para executar o envio do xml de alteração de endereço e retornar uma instância de HttpResponse. */ 
	global static HttpResponse executarEnvioXML( String method, String endpoint, String xml, Integer tempoTimeoutEmMilisegundos )
	{
		System.debug( 'Inicio - IntegracaoXmlHelper - executarEnvioXML.' );

		HttpRequest httpRequest = criarHttpRequest( method, endpoint, xml, tempoTimeoutEmMilisegundos ); 

        Http http = new Http();
        HttpResponse httpResponse = http.send( httpRequest );

		return httpResponse;
	}


	
	/** Utilizado para executar o serviço através de uma url e obter o HttpResponse para leitura de xml. */
	global static HttpResponse executarEnvio( String method, String endpoint, Integer tempoTimeoutEmMilisegundos )
	{
		System.debug( 'Inicio - IntegracaoXmlHelper - executarEnvio.' );

		HttpRequest httpRequest = criarHttpRequest( method, endpoint, tempoTimeoutEmMilisegundos ); 

        Http http = new Http();
        HttpResponse httpResponse = http.send( httpRequest );
        
        return httpResponse;
	}



	/** Constrói objeto HttpRequest e atribui documento xml */
	private static HttpRequest criarHttpRequest( String method, String endpoint, String xml, Integer tempoTimeoutEmMilisegundos ) 
	{
		System.debug( 'Inicio - IntegracaoXmlHelper - criarHttpRequest.' );
		
		HttpRequest httpRequest = new HttpRequest();
	
		Integer contentLength = xml.length();
		httpRequest.setMethod( method );
        httpRequest.setHeader( 'Content-type', 'text/xml' );
        httpRequest.setHeader( 'Content-Length', contentLength.format() );
        if ( tempoTimeoutEmMilisegundos != null && tempoTimeoutEmMilisegundos != 0 )
        {
        	httpRequest.setTimeout( tempoTimeoutEmMilisegundos );
        	System.debug( 'tempoTimeoutEmMilisegundos: ' + tempoTimeoutEmMilisegundos );
        }

		System.debug( 'endpoint: ' + endpoint );
        System.debug( 'xml: ' + xml );
		System.debug( 'method: ' + method );

        httpRequest.setEndpoint( endpoint ); 
        httpRequest.setBody( xml );

		return httpRequest;
	}



	/** Constrói objeto HttpRequest e atribui documento xml */
	private static HttpRequest criarHttpRequest( String method, String endpoint, Integer tempoTimeoutEmMilisegundos ) 
	{
		System.debug( 'Inicio - IntegracaoXmlHelper - criarHttpRequest.' );
		
		HttpRequest httpRequest = new HttpRequest();

        httpRequest.setMethod( method );
        httpRequest.setHeader( 'Content-type', 'text/xml' );
        
        if ( tempoTimeoutEmMilisegundos != null && tempoTimeoutEmMilisegundos != 0 )
        	httpRequest.setTimeout( tempoTimeoutEmMilisegundos );
        
		System.debug( 'endpoint: ' + endpoint );
        System.debug( 'method: ' + method );
        System.debug( 'tempoTimeoutEmMilisegundos: ' + tempoTimeoutEmMilisegundos );

        httpRequest.setEndpoint( endpoint ); 

		return httpRequest;
	}

}