/*****************************************************************************************************
    Desenvolvido por Orizonta Consultoria
    Objetivo: Utilizado para expor métodos de persistência no objeto RecordType - Tipo de Registro.

    Desenvolvido Por: Felipe Augusto da Silva Em: 27/03/2013
    Comentários: 
                     
*****************************************************************************************************/

public with sharing class OzDAORecordType 
{
	

	/* Utilizado para obter um mapa do tipo de registro do objeto informado por parâmetro. **/  
	public static Map<String, String> obterMapaTipoRegistroPorNomeObjeto( String nomeObjeto )
	{
		
		list<RecordType> listaRecordType = [SELECT name, id FROM RecordType WHERE sObjectType =:nomeObjeto AND isActive = true];
		Map<String, String> mapaTipoRegistro = new Map<String, String>();
		
		for( RecordType tipoRegistro : listaRecordType )
		{
			mapaTipoRegistro.put( tipoRegistro.name, tipoRegistro.id );
		}
		
		return mapaTipoRegistro;
	}
	
	
	
	/* Utilizado para obter um mapa do tipo de registro do objeto informado por parâmetro.**/ 
	public static List<String> obterListaNomeTipoRegistroPorNomeObjeto( String nomeObjeto )
	{
		List<RecordType> listaRecordType = null;
		listaRecordType = [SELECT name, id FROM RecordType WHERE sObjectType =:nomeObjeto AND isActive = true];
		List<String > listaNomesTiposRegistroObjeto = new List<String>();
		
		if(nomeObjeto == 'Account')
		{
			listaRecordType = [SELECT name, id FROM RecordType WHERE sObjectType =:nomeObjeto AND isActive = true  ];
		}
				
		for( RecordType tipoRegistro : listaRecordType )
		{
			listaNomesTiposRegistroObjeto.add( tipoRegistro.name );
		}

		return listaNomesTiposRegistroObjeto;
	}
	

	/* Utilizado para obter o id do tipo de registro pelo nome do objeto e pelo nome do tipo de registro informado.**/ 
	public static String obterIdTipoRegistroPorNomeObjetoENomeTipoRegistro ( String nomeObjeto, String nomeTipoRegistro )
	{
		Map<String, String> mapaTipoRegistro = obterMapaTipoRegistroPorNomeObjeto( nomeObjeto );
		
		return mapaTipoRegistro.get( nomeTipoRegistro );
	}
	
	
	/* Retorna a lista de tipo de registro do objeto informado **/
	public static List<RecordType> retornaListaDeTiposDeRegistros(String Objeto)
	{
		
		List<RecordType> tiposDeRegistros = [SELECT Name, Id FROM RecordType WHERE sObjectType=: Objeto AND isActive=true];
		return tiposDeRegistros;
	}
	
	
	
	/*	Retorna o nome do tipo de registro pelo Id**/
	public static String obtemNomeDotipoDeRegistro( String id )
	{
		
		try
		{
			String nome;
			List<RecordType> nomeDoTipoDeRegistro = [SELECT Name FROM RecordType WHERE Id =: id limit 1 ];
			
			for( RecordType tipoDeRegistro : nomeDoTipoDeRegistro )
			{
				nome = tipoDeRegistro.Name;
			}
			
			return nome;
			
		}
		catch( Exception e )
		{
			throw new DAOException( e.getMessage(), 'DAORecordType', 'obtemNomeDotipoDeRegistro', e );
			return null;
		}
	
	}
	

}