/**************************************************************************
   Desenvolvido por: Felipe Augusto da Silva;
   Data de Criação: 23/10/2013;
   Funcionalidade: Componente Oz que auxilia no consumo de integrações.
**************************************************************************/
global class OzIntegracaoResponse {


	/** Utilizado para ler response de integração do protocolo xml REST. Com apenas uma estrutura xml, exemplo:
		<alterarEnderecoDeEntregaResponse>
			<mensagem>Ok</mensagem>
		</alterarEnderecoDeEntregaResponse> 
	 */
	global static String obterResponseXmlRestDeUmaEstrutura( HttpResponse httpResponse, String tag )
	{
		System.debug( 'Inicio - OzIntegracaoResponse - lerHttpResponsePorTag.' );
		
		String mensagemRetorno = ''; 
		XmlStreamReader reader = httpResponse.getXmlStreamReader();
		Boolean tagInicioMensagem = false;

		while ( reader.hasNext() ) 
		{
			tagInicioMensagem = reader.getEventType() == XmlTag.START_ELEMENT && 
	    						tag == reader.getLocalName(); 

			if ( tagInicioMensagem ) 
	        {			
				mensagemRetorno = obterConteudoTag( reader );
				break;			
			}	
					
			reader.next();
		}							

		return mensagemRetorno;
	}
	
	
	
	/** Utilizado para ler response de integração do protocolo xml REST. Com apenas uma estrutura xml, exemplo:
		<SOAP-ENV:Envelope SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" 
						   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" 
						   xmlns:xsd="http://www.w3.org/2001/XMLSchema" 
						   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
						   xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/">
			<SOAP-ENV:Body>
				<ns1:CriaNovaCampanhaResponse xmlns:ns1="http://webservices2.Virtualtarget.com.br/WSDL">
				<return xsi:nil="999" xsi:type="xsd:integer"/>
				</ns1:CriaNovaCampanhaResponse >
			</SOAP-ENV:Body>
		</SOAP-ENV:Envelope> 
	 */
	global static String obterResponseXmlSoapDeUmaEstrutura( HttpResponse httpResponse )
	{   
		String msg = httpResponse.getBody();
		System.debug( 'httpResponse.getBody(): ' + msg );
		
		Dom.Document document = new Dom.Document();
        document.load( msg );
		Dom.XMLNode envelope = document.getRootElement();        
        Dom.XMLNode body = envelope.getChildElements()[0];        
        
        String user_createResult = '';
        
        for ( Dom.XMLNode child : body.getChildElements() ) 
        {
            for ( Dom.XMLNode subchild : child.getChildElements() ) 
            {
                return subchild.getText();
            }
        }    
                    
        return null;
	}
    
	
	
	/** Utilizado para obter o conteudo do atributo xml */
   	global static String obterConteudoTag( XmlStreamReader reader ) 
   	{
   		System.debug( 'Inicio - OzIntegracaoResponse - obterConteudoAtributo.' );
    	String result = '';

     	while( reader.hasNext() ) 
     	{
        	if ( reader.getEventType() == XmlTag.END_ELEMENT ) 
        	{
           		break;
        	} 
        	else if ( reader.getEventType() == XmlTag.CHARACTERS ) 
        	{
           		result = reader.getText();
        	}
        	reader.next();
     	}

     	return result;
   }

}