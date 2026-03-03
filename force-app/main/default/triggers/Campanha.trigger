trigger Campanha on Campaign (after insert,before update,after update) 
{
	public final String tipoDeRegistroFilho = '012i0000001EExr';
	
	Campaign camp = new Campaign();
	List<Campaign> listaCampanhas = new List<Campaign>();
	List<Campaign> listaCampanhasFilhos = new List<Campaign>();  
	List<Id> listaIdCampanhasAtualizarCustos = new List<ID>();
	List<Id> listaIdCampanhasPai = new List<ID>();
	Boolean beforeInsert = false;
	Boolean beforeUpdate = false;
	Boolean afterInsert  = false;
	Boolean afterUpdate  = false;
	Integer dias = 0,diasDeAcrecimo = 0;
	Date dataInicialCampanha;
	Date dataFinalCampanha;
	String name = '';	
	
	if( (trigger.isBefore) && (trigger.isInsert) )
	{
		beforeInsert = true;
	}
	
	if( (trigger.isBefore) && (trigger.isUpdate) )
	{
		beforeUpdate = true;
	}
	if( (trigger.isAfter) && (trigger.isInsert) )
	{
		afterInsert = true;
	}
	if( (trigger.isAfter) && (trigger.isUpdate) )
	{
		afterUpdate = true;
	}
		
		
		
	for( Campaign campanha: trigger.new )
	{
		
		if( beforeInsert )
		{
			if( campanha.DiasRestantesExpiracao__c == null )
			{
				campanha.DiasRestantesExpiracao__c = 150;
			}
		}			
		
		
		if(( afterInsert ) && ( campanha.RecordTypeId != tipoDeRegistroFilho ))
		{
			
			
			for( Integer i = 2; i <= 7 ; i++ )
			{
								
				if(!(i == 7))
				{
					dias = (150 - ( (30*(i-1))));
					name = 'Fase ' + i + ' '+ campanha.Name + ' ' +dias + 'D';
				}
				else
				{
				    dias = -30;
				    name = 'Fase ' + i + ' ' + campanha.Name + '+30D' ;				   
				}
				
				diasDeAcrecimo = (i-1) * 30;
				
								    
				listaCampanhas.add(new Campaign( Name = name ,RecordTypeId= tipoDeRegistroFilho , C_digo_da_Origem__c = campanha.C_digo_da_Origem__c ,
											     ParentId = campanha.Id, DiasRestantesExpiracao__c = dias , StartDate = campanha.StartDate + diasDeAcrecimo,
											     Type = campanha.Type, Status = campanha.Status , CustoEstimadoCorreio__c = 0 ,CustoEstimadoAtendimentoTelefonico__c = 0,
											     CustoEstimadoCorreioEletronico__c = 0,CustoEstimadoSms__c = 0,CustoRealCorreio__c = 0,
									 		     CustoRealAtendimentoTelefonico__c = 0,CustoRealCorreioEletronico__c = 0,CustoRealSms__c = 0, IsActive = true
											   ));
											
			}						
			
			if(!listaCampanhas.isEmpty())
				insert listaCampanhas;
				listaCampanhas.clear();
		}	
		
		if( beforeUpdate )
		{
			if( campanha.RecordTypeId != tipoDeRegistroFilho )
			{	
				listaCampanhasFilhos =[ SELECT Id,ParentId,CustoEstimadoCorreio__c,CustoEstimadoAtendimentoTelefonico__c,CustoEstimadoCorreioEletronico__c,CustoEstimadoSms__c,
									 		   CustoRealCorreio__c,CustoRealAtendimentoTelefonico__c,CustoRealCorreioEletronico__c,CustoRealSms__c
										FROM Campaign
										WHERE ParentId =: campanha.Id
		  		  						];
				
				if( campanha.RecordTypeId != tipoDeRegistroFilho )
				{	
					campanha.TotalCustoEstimadoCorreio__c = 0;	
					campanha.TotalCustoEstimadoAtendimentoTelefonico__c = 0;
					campanha.TotalCustoEstimadoCorreioEletronico__c = 0;
					campanha.TotalCustoEstimadoSms__c = 0;
					campanha.TotalCustoRealCorreio__c = 0;	
					campanha.TotalCustoRealAtendimentoTelefonico__c = 0;
					campanha.TotalCustoRealCorreioEletronico__c = 0;
					campanha.TotalCustoRealSms__c = 0;
							  		  
								  		  
					for( Campaign subCampanha: listaCampanhasFilhos )
					{
							
						if( subCampanha.ParentId == campanha.Id)
						{
							//Estimado
							if( subCampanha.CustoEstimadoCorreio__c != NULL)
								campanha.TotalCustoEstimadoCorreio__c += subCampanha.CustoEstimadoCorreio__c;
								
							if( subCampanha.CustoEstimadoAtendimentoTelefonico__c != NULL)	
								campanha.TotalCustoEstimadoAtendimentoTelefonico__c += subCampanha.CustoEstimadoAtendimentoTelefonico__c;
							
							if( subCampanha.CustoEstimadoCorreioEletronico__c != NULL)		
								campanha.TotalCustoEstimadoCorreioEletronico__c += subCampanha.CustoEstimadoCorreioEletronico__c;
								
							if( subCampanha.CustoEstimadoSms__c != NULL)									
								campanha.TotalCustoEstimadoSms__c += subCampanha.CustoEstimadoSms__c;
							
							
							// Real	
							if( subCampanha.CustoRealCorreio__c != NULL)									
								campanha.TotalCustoRealCorreio__c += subCampanha.CustoRealCorreio__c;
								
							if( subCampanha.CustoRealAtendimentoTelefonico__c != NULL)									
								campanha.TotalCustoRealAtendimentoTelefonico__c += subCampanha.CustoRealAtendimentoTelefonico__c;
								
							if( subCampanha.CustoRealCorreioEletronico__c != NULL)									
								campanha.TotalCustoRealCorreioEletronico__c += subCampanha.CustoRealCorreioEletronico__c;
								
							if( subCampanha.CustoRealSms__c != NULL)									
								campanha.TotalCustoRealSms__c += subCampanha.CustoRealSms__c;									
																																				
																	
						}
					}	
				}
			}
		}
						
		
		if( afterUpdate )
		{	
			if( campanha.RecordTypeId == tipoDeRegistroFilho )
			{
					
					camp = [ SELECT Id, TotalCustoEstimadoCorreio__c, TotalCustoEstimadoAtendimentoTelefonico__c , TotalCustoEstimadoCorreioEletronico__c,TotalCustoEstimadoSms__c,TotalCustoRealCorreio__c,TotalCustoRealAtendimentoTelefonico__c,TotalCustoRealCorreioEletronico__c,TotalCustoRealSms__c
									  FROM Campaign 
									  WHERE Id =: campanha.ParentId
									  ];
					
					listaCampanhasFilhos =[ SELECT Id,ParentId,CustoEstimadoCorreio__c,CustoEstimadoAtendimentoTelefonico__c,CustoEstimadoCorreioEletronico__c,CustoEstimadoSms__c,
											       CustoRealCorreio__c,CustoRealAtendimentoTelefonico__c,CustoRealCorreioEletronico__c,CustoRealSms__c
											FROM Campaign 
											WHERE ParentId =: camp.Id
		  		  						  ];
				
					if( campanha.RecordTypeId != tipoDeRegistroFilho )
					{	
						camp.TotalCustoEstimadoCorreio__c = 0 + campanha.CustoEstimadoCorreio__c;	
						camp.TotalCustoEstimadoAtendimentoTelefonico__c = 0 + campanha.CustoEstimadoAtendimentoTelefonico__c;
						camp.TotalCustoEstimadoCorreioEletronico__c = 0 + campanha.CustoEstimadoCorreioEletronico__c;
						camp.TotalCustoEstimadoSms__c = 0 + campanha.CustoEstimadoCorreio__c ;
						
						camp.TotalCustoRealCorreio__c = 0 + campanha.CustoRealCorreio__c;	
						camp.TotalCustoRealAtendimentoTelefonico__c = 0 + campanha.CustoRealAtendimentoTelefonico__c;
						camp.TotalCustoRealCorreioEletronico__c = 0 + campanha.CustoRealCorreioEletronico__c;
						camp.TotalCustoRealSms__c = 0 + campanha.CustoRealSms__c;
								  		  
									  		  
						for( Campaign subCampanha: listaCampanhasFilhos )
						{
								
							if( subCampanha.ParentId == campanha.Id)
							{
								if( subCampanha.CustoEstimadoCorreio__c != NULL)
									camp.TotalCustoEstimadoCorreio__c += subCampanha.CustoEstimadoCorreio__c;
									
								if( subCampanha.CustoEstimadoAtendimentoTelefonico__c != NULL)	
									camp.TotalCustoEstimadoAtendimentoTelefonico__c += subCampanha.CustoEstimadoAtendimentoTelefonico__c;
								
								if( subCampanha.CustoEstimadoCorreioEletronico__c != NULL)		
									camp.TotalCustoEstimadoCorreioEletronico__c += subCampanha.CustoEstimadoCorreioEletronico__c;
									
								if( subCampanha.CustoEstimadoSms__c != NULL)									
									camp.TotalCustoEstimadoSms__c += subCampanha.CustoEstimadoSms__c;
									
									
									
								if( subCampanha.CustoRealCorreio__c != NULL)									
									camp.TotalCustoRealCorreio__c += subCampanha.CustoRealCorreio__c;
									
								if( subCampanha.CustoRealAtendimentoTelefonico__c != NULL)									
									camp.TotalCustoRealAtendimentoTelefonico__c += subCampanha.CustoRealAtendimentoTelefonico__c;
									
								if( subCampanha.CustoRealCorreioEletronico__c != NULL)									
									camp.TotalCustoRealCorreioEletronico__c += subCampanha.CustoRealCorreioEletronico__c;
									
								if( subCampanha.CustoRealSms__c != NULL)									
									camp.TotalCustoRealSms__c += subCampanha.CustoRealSms__c;									
																																				
									
									
							}
						}	
					}				
					update camp;
			}

		}
	}
}