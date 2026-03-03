/*********************************************************************************************
    Desenvolvido por Avanxo Consultoria    
    Autor: Rodrigo Donha
    Criado: 26/09/2013
*********************************************************************************************/

public class OzVisualForce 
{
	
	/** Utilizador para Obter o parametro passado via URL */
	public static String obterParametroUrl(String parametro)
	{		
		 return  ApexPages.currentPage().getParameters().get( parametro );		
	}	
	
	
	
	/** Metodo utilizado para gera link HTTP para o registro criado */
	public static String gerarLinkRegistroPeloId(String ID)
	{
		String link;
		link = URL.getSalesforceBaseUrl().toExternalForm().replace('visual.','sales').replace('c.','');
		link += '/' +ID;
	
		return link.trim();
	}
	
	
	
	/** Retorna o link base do servidor atual que está sendo usado 
	    Exemplo: "http://cs9.salesfore.com/" */
	public static String obterLinkSalesforceBase()
	{
		return URL.getSalesforceBaseUrl().toExternalForm().replace('visual.','sales').replace('c.','') + '/';
	}
	
	
	
	
	/** Adiciona String como item da lista de opção recebida e retorna a lista */
	public static List<SelectOption> AdicionarItemEmOptionList(List<SelectOption> listaOpcao ,String valor)
	{
		listaOpcao.add(new selectOption(valor, valor));
		
		return listaOpcao;
	}
	
	
	
}