/**********************************************************************************************************************************************************************

 Desenvolvido por Avanxo Brasil

 Classe testada: OzVisualForceHelper.

 Métodos testados: obterParametroUrl, adicionarMapaItensEmSelectOptionList, adicionarListaItensEmSelectOptionList.

**********************************************************************************************************************************************************************/

@isTest
public class TestOzVisualForceHelper 
{
	 
	public TestOzVisualForceHelper()
	{
		testObterParametroUrl();
		testAdicionarMapaItensEmSelectOptionList();
		testAdicionarListaItensEmSelectOptionList();
		testAdicionarListaItensEmSelectOptionList();
	}
	
	/** Testa o método obterParametroUrl */
    static testMethod void testObterParametroUrl() 
    {
    	try
    	{
    		OzVisualForceHelper.obterParametroUrl( null );
    	}
    	catch( Exception e )
    	{
    		
    	}
        OzVisualForceHelper.obterParametroUrl( 'idParametro' );
    }
    
    
    
    /** Testa o método adicionarMapaItensEmSelectOptionList */
    static testMethod void testAdicionarMapaItensEmSelectOptionList() 
    {
    	Map<String,String> mapaIdEValorDoSelectOptionList = new Map<String,String>();
    	try
    	{
    		OzVisualForceHelper.adicionarMapaItensEmSelectOptionList( mapaIdEValorDoSelectOptionList );
    	}
    	catch( Exception e )
    	{
    		
    	}
    	mapaIdEValorDoSelectOptionList.put( '1', 'Primeiro Valor' );
        OzVisualForceHelper.adicionarMapaItensEmSelectOptionList( mapaIdEValorDoSelectOptionList );
    }
    
    
    
    /** Testa o método adicionarListaItensEmSelectOptionList */
    static testMethod void testAdicionarListaItensEmSelectOptionList() 
    {
    	List<String> listaValoresDoSelectOptionList = new List<String>();
    	try
    	{
    		OzVisualForceHelper.adicionarListaItensEmSelectOptionList( listaValoresDoSelectOptionList );
    	}
    	catch( Exception e )
    	{
    		
    	}
    	listaValoresDoSelectOptionList.add( 'Primeiro Valor' );
        OzVisualForceHelper.adicionarListaItensEmSelectOptionList( listaValoresDoSelectOptionList );
    }
    
}