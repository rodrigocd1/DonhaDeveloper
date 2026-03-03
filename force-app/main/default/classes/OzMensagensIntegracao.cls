/**************************************************************************
   Desenvolvido por: Felipe Augusto da Silva;
   Data de Criação: 23/10/2013;
   Funcionalidade: Oz Constantes Integração.
**************************************************************************/
global class OzMensagensIntegracao {

	global static String MENSAGEM_HTTP_RESPONSE_NULL = 'O objeto HttpResponse é igual a null. ';


	/** Utilizado para obter mensagem de status por status code do httpResponse. */
	global static String obterMensagemErroHtmlPorStatusCodeDoHttpResponse( String url, String xml, HttpResponse httpResponse )
	{
		String mensagemRetorno = '';
		Integer statusCodeHttpResponse = httpResponse.getStatusCode();
		String bodyResponse = httpResponse.getBody();
		if ( statusCodeHttpResponse == null )
		{
			mensagemRetorno = 'Não foi possível realizar a integração. Status Code indefinido';
		}
		else if( statusCodeHttpResponse != null && statusCodeHttpResponse != 200 ) 
		{
			mensagemRetorno = 'Não foi possível realizar a integração. Status Code do HttpResponse: ' + statusCodeHttpResponse + '';
		}
				
		return '<font face="verdana"><br/>Ocorreu erro inesperado na integração SalesForce. ' +
			   '<br/><b>URL de execução:</b> ' + url + ';' + 
			   '<br/><b>XML de Envio:</b> <textarea rows="20" cols="40" style="border:none;">' + xml + '</textarea>;' +
			   '<br/><b>Mensagem da Exceção:</b> ' + mensagemRetorno + ';' +
			   '<br/><b>Xml de Resposta:</b> <textarea rows="20" cols="40" style="border:none;">' + bodyResponse + '</textarea></font>';
	} 


	/** Utilizado para obter mensagem de status por status code do httpResponse. */
	global static String obterMensagemErroPorStatusCodeDoHttpResponse( String url, String xml, HttpResponse httpResponse )
	{
		String mensagemRetorno = '';
		Integer statusCodeHttpResponse = httpResponse.getStatusCode();
		String bodyResponse = httpResponse.getBody();
		if ( statusCodeHttpResponse == null )
		{
			mensagemRetorno = 'Não foi possível realizar a integração. Status Code indefinido';
		}
		else if( statusCodeHttpResponse != null && statusCodeHttpResponse != 200 ) 
		{
			mensagemRetorno = 'Não foi possível realizar a integração. Status Code do HttpResponse: ' + statusCodeHttpResponse + '';
		}
				
		return 'Ocorreu erro inesperado na integração SalesForce. \r\n\r\n' +
			   'URL de execução: ' + url + ';\r\n' + 
			   'XML de Envio: ' + xml + ';\r\n' +
			   'Mensagem da Exceção: ' + mensagemRetorno + ';\r\n' +
			   'Xml de Resposta: ' + bodyResponse + '\r\n';
	} 


 	/** Utilizado para montar mensagem de erro de integração. */
    global static String obterMensagemErroIntegracao( String url, String xml, String mensagemExcecao )
    {
		return 'Ocorreu erro inesperado na integração SalesForce. \r\n\r\n' +
			   'URL de execução: ' + url + ';\r\n' + 
			   'XML de Envio: ' + xml + ';\r\n' +
			   'Mensagem da Exceção: ' + mensagemExcecao + ';\r\n';
	}


	/** Utilizado para montar mensagem de erro de integração. */
    global static String obterMensagemErroHtmlIntegracao( String url, String xml, String mensagemExcecao )
    {
		return '<font face="verdana"><br/>Ocorreu erro inesperado na integração SalesForce.' +
			   '<br/><b>URL de execução:</b>' + url + ';' + 
			   '<br/><b>XML de Envio:</b><textarea rows="20" cols="40" style="border:none;">' + xml + '</textarea>;' +
			   '<br/><b>Mensagem da Exceção:</b>' + mensagemExcecao + '; </font>';
	}

}