/**************************************************************************
   Desenvolvido por: Rodrigo Donha.
   Data de Criação: 03/10/2013
   Funcionalidade: Classe auxiliar no redirecionamento de paginas em visual force. 
**************************************************************************/
public class OzVisualForcePageReferences 
{
	
	
	
	/** Cria PageReference por identificador de um objeto (redireciona para a tela do registro informado). */
	public static PageReference redirecionarTelaObjeto ( String idObjeto )
	{
		PageReference page = null;
		if( idObjeto == null )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o Id do Objeto. ', 'OzVisualForcePageReferences', 
														   'redirecionarTelaObjeto' );
		}
		
		String pagina = '/' + idObjeto + '/o';
		page = new PageReference( pagina.trim() );
		
		return page;		
	}
	


	/** Cria PageReferece para redirecionar para pagina visualforce informada por parâmetro. */
	public static PageReference redirecionarParaPaginaVisualForceDoRegistro( String idRegistro )
	{
		if( idRegistro == null )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o id do registro. ', 'OzVisualForcePageReferences', 
														   'redirecionarParaPaginaVisualForceDoRegistro' );
		}
		
		return new PageReference( '/' + idRegistro.trim() );		
	}
	
	
	
	/** Cria PageReferece para redirecionar para pagina visualforce informada por parâmetro. */
	public static PageReference redirecionarPaginaVisualForce( String nomeDaPagina )
	{
		String link = '/apex/' + nomeDaPagina;		
		
		return new PageReference( link.trim() );		
	}
	


	/** Cria PageReferece para redirecionar para pagina visualforce pelos parâmetros informados. */
	public static PageReference redirecionarParaVisualForcePorParametros( String nomeDaPagina, Map<String, String> mapaChaveValorUrl )
	{
		if( nomeDaPagina == null || nomeDaPagina == '' )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o nome da pagina. ', 'OzVisualForcePageReferences', 
														   'redirecionarParaVisualForcePorParametros' );
		}
		
		if( mapaChaveValorUrl == null || mapaChaveValorUrl.isEmpty() )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o mapa com a chave e os valores. ', 'OzVisualForcePageReferences', 
														   'redirecionarParaVisualForcePorParametros' );
		}
		
		String url = obterStringUrlPorMultiplosParametros( '/apex/' + nomeDaPagina.trim(), mapaChaveValorUrl );
		
		return new PageReference( url );		
	}



	/** Cria PageReferece para redirecionar para pagina visualforce pelo parâmetro informado. */
	public static PageReference redirecionarParaVisualForcePorParametro( String nomeDaPagina, String parametro, String valorParametro )
	{
		if( nomeDaPagina == null || nomeDaPagina == '' )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o nome da pagina. ', 'OzVisualForcePageReferences', 
														   'redirecionarParaVisualForcePorParametro' );
		}
		
		if( parametro == null || parametro == '' )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o parâmetro. ', 'OzVisualForcePageReferences', 
														   'redirecionarParaVisualForcePorParametro' );
		}
		
		if( valorParametro == null || valorParametro == '' )		
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar o valor do parâmetro. ', 'OzVisualForcePageReferences', 
														   'redirecionarParaVisualForcePorParametro' );
		}
		
		return new PageReference( '/apex/' + nomeDaPagina.trim() + '?' + parametro.trim() + '=' + valorParametro.trim() );		
	}



	/** Utilizado para montar a url a partir de uma url e um mapa de parametro de chave e valor. */
	private static String obterStringUrlPorMultiplosParametros( String url, Map<String, String> mapaChaveValorUrl ) 
	{
		if ( url == null || url == '' )
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar a urlInicial. ', 'OzVisualForcePageReference',
														   'obterStringUrlPorMultiplosParametros' );
		}

		if ( mapaChaveValorUrl == null )
		{
			throw new OzVisualForcePageReferenceException( 'É obrigatório informar a urlInicial. ', 'OzVisualForcePageReference',
														   'obterStringUrlPorMultiplosParametros' );
		}
		
		String urlRetorno = url;
		Integer contador = 0;
		for ( String parametro : mapaChaveValorUrl.keySet() )
		{
			if (!urlRetorno.contains('?'))
			{
				urlRetorno += '?';
			}
			
        	String valorParametro = mapaChaveValorUrl.get( parametro );
			if (( contador == 0 ))
			{
				urlRetorno +=  parametro + '=' + valorParametro; 
			}
			else
			{
				urlRetorno += '&' + parametro + '=' + valorParametro;
			}
			contador++;
        }

		return urlRetorno;
	}

}