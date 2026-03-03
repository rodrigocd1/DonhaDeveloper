/**************************************************************************
   Desenvolvido por: Felipe Augusto da Silva
   Data de Criação: 04/10/2013
   Funcionalidade: Utilizado para expor métodos de persistência do objeto OrgWideEmailAdress.
   				   E-mail de toda organização: Um endereço de email de toda a organização associa um endereço de email a um perfil de 
   				   							   usuário. Cada usuário no perfil pode enviar emails utilizando esse endereço. 
											   Os usuários compartilharão o mesmo nome de visualização e endereço de email.
											   
   				   OrgWideEmailAdress: http://www.salesforce.com/us/developer/docs/api/Content/sforce_api_objects_orgwideemailaddress.htm 
**************************************************************************/
public class DAOOrgWideEmailAddress {



	/** Utilizado para retornar o objeto OrgWideEmailAdress pela string de endereço de e-mail informado. */
	public static OrgWideEmailAddress obterOrgWideEmailAddressPorEmail( String email )
	{
		OrgWideEmailAddress owea = null;
		try
		{
			owea = [select Id from OrgWideEmailAddress where Address =: email];	
		}
		catch ( Exception e )
		{
			throw new DAOException( 'Ocorreu um erro inesperado ao tentar obterOrgWideEmailAddressPorEmail. Detalhes do erro: ' + e.getMessage(), 
									'DAOOrgWideEmailAddress', 'obterOrgWideEmailAddressPorEmail', e );
		}
		
		return owea;
	}


}