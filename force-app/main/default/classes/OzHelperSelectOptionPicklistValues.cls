/*********************************************************************************************
    Desenvolvido por Orizonta Consultoria
    Atualização: Adicionado métodos para obterlista de produtos, e condicinais a query.
    Autor: Felipe Silva
    Criado: 26/09/2013
*********************************************************************************************/
public class OzHelperSelectOptionPicklistValues 
{
	/*Obtém à lista de opções de um campo, do objeto especificado e campo informado*/
	public static List<SelectOption> obterListaSelectOptionPorObjetoECampo( String nomeApiObject, String nomeApiCampo )
	{
		List<SelectOption> options = new List<SelectOption>();

 		Schema.SObjectType targetType = Schema.getGlobalDescribe().get( nomeApiObject );
    	Sobject objectName = targetType.newSObject();
  		Schema.sObjectType sObjectType = objectName.getSObjectType(); 
		Schema.DescribeSObjectResult describeSobjectResult = sObjectType.getDescribe();       

	  	Map<String, Schema.SObjectField> fieldMap = describeSobjectResult.fields.getMap(); 
		List<Schema.PicklistEntry> values = fieldMap.get( nomeApiCampo ).getDescribe().getPickListValues();

		options.add( new SelectOption( '', ' - Selecione - ' ) );
	  	for ( Schema.PicklistEntry a : values )
	  	{ 
			options.add( new SelectOption( a.getLabel(), a.getValue() ) ); 
	  	}
	  
	  	return options;
	}
	
	
	
	/*Obtém à lista de opções de um campo, do objeto especificado e campo informado*/
	public static List<SelectOption> obterListaTipoRegistroSelectOptionPorObjeto( String nomeApiObject )
	{
		List<SelectOption> options = new List<SelectOption>();
		options.add( new SelectOption( '', ' - Selecione - ' ) );
		
		List<String> listaNomesTiposRegistros = DAORecordType.obterListaNomeTipoRegistroPorNomeObjeto( nomeApiObject );
	  	for ( String nome : listaNomesTiposRegistros )
	  	{ 
			options.add( new SelectOption( nome, nome ) ); 
	  	}
	  
	  	return options;
	}
	
}