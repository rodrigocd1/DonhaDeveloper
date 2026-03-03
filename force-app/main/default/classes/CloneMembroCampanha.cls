public class CloneMembroCampanha 
{
	public static void clonarMembroDaCampanha( CampaignMember membroCampanha, Campaign campanha )
	{
		CampaignMember novoMembro = membroCampanha.clone();
		
		novoMembro.flagCartaLida__c = false;
		novoMembro.flagEmailLido__c = false;
		novoMembro.flagLigacaoRecebida__c = false;
		novoMembro.flagSmsLido__c = false;
		
		novoMembro.CampaignId = campanha.Id;
		novoMembro.flagRemanejado__c = false;
		
		insert novoMembro;
		
	
	}
	
	public static boolean verificarClienteInformado( Map<ID,Campaign> mapCampanhas , CampaignMember membroCampanha )
	{
		Decimal DiasRestantesExpiracao = ( mapCampanhas.get(membroCampanha.CampaignId).DiasRestantesExpiracao__c );
		
		if(( DiasRestantesExpiracao == 150 ) && ( ( membroCampanha.flagCartaLida__c ) || ( membroCampanha.flagLigacaoRecebida__c ) 		 ))
		{
			return true;
		}
		else if( ( DiasRestantesExpiracao == 120 ) && ( ( membroCampanha.flagCartaLida__c ) || ( membroCampanha.flagLigacaoRecebida__c ) ))
		{
			return true;
		}
		else if( ( DiasRestantesExpiracao == 90 ) && ( ( membroCampanha.flagCartaLida__c ) || ( membroCampanha.flagLigacaoRecebida__c ) || ( membroCampanha.flagSmsLido__c ) || ( membroCampanha.flagEmailLido__c )  ))
		{
			return true;
		}
		else if( ( DiasRestantesExpiracao == 60 ) && ( ( membroCampanha.flagCartaLida__c ) || ( membroCampanha.flagLigacaoRecebida__c ) ))
		{
			return true;
		}
		else if( ( DiasRestantesExpiracao == 30 ) && ( ( membroCampanha.flagCartaLida__c ) || ( membroCampanha.flagLigacaoRecebida__c ) || ( membroCampanha.flagSmsLido__c ) || ( membroCampanha.flagEmailLido__c )  ))
		{
			return true;
		}
		else if( ( DiasRestantesExpiracao == 0 ) && ( ( membroCampanha.flagEmailLido__c ) || ( membroCampanha.flagLigacaoRecebida__c ) ))
		{
			return true;
		}		
		
		return false;
		
	
	}
}