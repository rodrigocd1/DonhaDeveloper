trigger MembroDaCampanha on CampaignMember (before update) 
{
	List<ID> listaIdCampanha = new List<ID>();
	Map<ID,Campaign> mapCampanhas = new Map<ID,Campaign>();
	
	List<Campaign> listaCampanhas = new List<Campaign>();
	List<Campaign> listaCampanhasFilho = new List<Campaign>();
	Integer diasRestantesExpiracao;
	
	
	for( CampaignMember membroCampanha: trigger.new )
	{		
		listaIdCampanha.add( membroCampanha.CampaignId );	
	}
	
	listaCampanhas = [SELECT ID,Name, DiasRestantesExpiracao__c,ParentId From Campaign Where Id IN : (listaIdCampanha) ];
	
	for(Campaign campanha: listaCampanhas)
	{
		mapCampanhas.put(campanha.id,campanha);
	}	
	
	try
	{	
		for( CampaignMember membroCampanha: trigger.new )
		{		
			if(  ( membroCampanha.flagRemanejado__c == false ) && (membroCampanha.statusOferta__c != 'Aceita' ))
			{
				if( ( CloneMembroCampanha.verificarClienteInformado( mapCampanhas , membroCampanha ))  )
				{
					Campaign campanha = new Campaign();
					
					if ( MapCampanhas.get( membroCampanha.CampaignId).DiasRestantesExpiracao__c == 150 )
					{
						campanha = [SELECT Id,DiasRestantesExpiracao__c From Campaign Where ParentId =: membroCampanha.CampaignId AND DiasRestantesExpiracao__c =: ( ( MapCampanhas.get( membroCampanha.CampaignId).DiasRestantesExpiracao__c ) - 30 ) ];						
					}
					else
					{
						campanha = [SELECT Id,DiasRestantesExpiracao__c From Campaign Where ParentId =: mapCampanhas.get( membroCampanha.CampaignId ).ParentId  AND DiasRestantesExpiracao__c =: ( ( MapCampanhas.get( membroCampanha.CampaignId).DiasRestantesExpiracao__c ) - 30 ) ];			
					}					
					
					CloneMembroCampanha.clonarMembroDaCampanha( membroCampanha, campanha);
					
					membroCampanha.flagRemanejado__c = true;
				}
			}
		
		}
	}
	catch(exception e)
	{
		
	}
	

}