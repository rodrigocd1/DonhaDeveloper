/**********************************************************************************************************************************************************************

 @description Classe helper com métodos utilizados em páginas VisualForce.
 @author Avanxo - Rodrigo Donha
 @date 26/03/2014

**********************************************************************************************************************************************************************/

public class OzVisualForceHelper 
{
	 
	/** 
		@description Utilizador para Obter o parametro passado via URL.
		@param parametro String do parametro da Url
		@return String Valor do parametro na url.
		@author Avanxo - Rodrigo Donha
 		@date 26/03/2014
 	*/
	public static String obterParametroUrl( String parametro )
	{
		system.debug( 'Início do método: obterParametroUrl' );
		if( parametro == null || parametro == '' )
		{
			throw new OzVisualForceHelperException( 'O parâmetro informado esta nulo.', 'OzVisualForceHelper', 'obterParametroUrl' );
		}
		
		system.debug( 'Fim do método: obterParametroUrl' );		
		return  ApexPages.currentPage().getParameters().get( parametro );		
	}
	
	
	
	/** 
		@description Adiciona valores em uma lista de SelectOption através de um mapa com Chaves e Valores a serem inseridos.
		@param mapaIdEValorDoSelectOptionList Mapa que possui Id e o valor do SelectOption
		@return List<SelectOption> Lista de SelectOption criada a partir do mapaIdEValorDoSelectOptionList
		@author Avanxo - Rodrigo Donha
 		@date 26/03/2014
 	*/
	public static List<SelectOption> adicionarMapaItensEmSelectOptionList( Map<String,String> mapaIdEValorDoSelectOptionList )
	{
		system.debug( 'Início do método: adicionarMapaItensEmSelectOptionList' );
		if( mapaIdEValorDoSelectOptionList == null || mapaIdEValorDoSelectOptionList.isEmpty() )
		{
			throw new OzVisualForceHelperException( 'O parâmetro informado esta nulo.', 'OzVisualForceHelper', 'adicionarMapaItensEmSelectOptionList' );
		}
		
		List<SelectOption> listaOpcao = new List<SelectOption>();
		
		for( String chave : mapaIdEValorDoSelectOptionList.keySet() )
		{
			listaOpcao.add( new selectOption( chave, mapaIdEValorDoSelectOptionList.get( chave ) ) );
		}
		
		system.debug( 'Fim do método: adicionarMapaItensEmSelectOptionList' );	
		return listaOpcao;
	}
	
	
	
	/** 
		@description Adiciona valores em uma lista de SelectOption através de uma lista com Valores a serem inseridos, as chaves serão iguais aos valores. 
		@param listaValoresDoSelectOptionList List<String> que apenas o valor do SelectOption que será utilizado com identificador também.
		@return List<SelectOption> Lista de SelectOption criada a partir do listaValoresDoSelectOptionList
		@author Avanxo - Rodrigo Donha
 		@date 26/03/2014
 	*/
	public static List<SelectOption> adicionarListaItensEmSelectOptionList( List<String> listaValoresDoSelectOptionList )
	{
		system.debug( 'Início do método: adicionarListaItensEmSelectOptionList' );
		if( listaValoresDoSelectOptionList == null || listaValoresDoSelectOptionList.isEmpty() )
		{
			throw new OzVisualForceHelperException( 'O parâmetro informado esta nulo.', 'OzVisualForceHelper', 'adicionarListaItensEmSelectOptionList' );
		}
		
		List<SelectOption> listaOpcao = new List<SelectOption>();
		
		for( String valor : listaValoresDoSelectOptionList )
		{
			listaOpcao.add( new selectOption( valor, valor ) );
		}
		
		system.debug( 'Fim do método: adicionarListaItensEmSelectOptionList' );	
		return listaOpcao;
	}
	
}