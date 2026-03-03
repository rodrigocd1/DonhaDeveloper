global class AC_ValidarHorarioComercialBot
{
    
    // Para a classe funcionar no BOT deve-se adiciona a mesma no permission set
    // sfdc.chatbot.service.permset
    
    
    global class Input 
  	{
    	@InvocableVariable(required=true)
    	global String nomeHorarioComercial;
  	}
    
    
    global class Output 
    {
        @InvocableVariable(required=true)
    	global Boolean dentroDoHorarioComercial;                
        
  	}
    
    
     @InvocableMethod(label='Validar Horario Comercial')
  	 global static List< Output > ValidarHoraComercial(List< Input > transcripts) 
     {
		
                                  
        List< Output > listaDeRetorno = new  List< Output >();
         
        for(Input input: transcripts)
        {
            String nomeHorarioComercial = input.nomeHorarioComercial;
            
            Output retorno = new Output();	
            
            // Get the default business hours
            BusinessHours businessHour = [SELECT Id FROM BusinessHours WHERE Name =: nomeHorarioComercial  ];
            
            // Create Datetime on May 28, 2013 at 1:06:08 AM in the local timezone.
            Datetime targetTime = Datetime.now();
            
            // Find whether the time is within the default business hours
            Boolean isWithin = BusinessHours.isWithin(businessHour.id, targetTime);
            
            retorno.dentroDoHorarioComercial = isWithin;
             
            listaDeRetorno.add(retorno);
            
        }
                         
         return listaDeRetorno;
  	}

}