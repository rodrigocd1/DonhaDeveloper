global class ObterEnderecoPorCepViaBot 
{

    // Para a classe funcionar no BOT deve-se adiciona a mesma no permission set
    // sfdc.chatbot.service.permset
    // 
    
    global class CEPInput 
  	{
    	@InvocableVariable(required=true)
    	global String cep;
  	}
    
    
    global class CEPOutput 
    {
        @InvocableVariable(required=true)
    	global String estado;
        
        @InvocableVariable(required=true)
    	global String cidade;
        
    	@InvocableVariable(required=true)
    	global String logradouro;        
        
  	}
	
      @InvocableMethod(label='Buscar CEP')
  	 global static List<CEPOutput> buscarCEP(List<CEPInput> transcripts) 
     {
		
        ControllerConsultaCep ControllerConsultaCep = new ControllerConsultaCep(); 
        
         
         
        List< CEPOutput > listaEnderecos = new  List< CEPOutput >();
         
        for(CEPInput input: transcripts)
        {
            CEPOutput endereco = new CEPOutput();
			
            ControllerConsultaCep.cepBusca = input.cep;
            ControllerConsultaCep.buscarCEP();
            
            endereco.estado = ControllerConsultaCep.endereco.uf;
            endereco.cidade = ControllerConsultaCep.endereco.localidade;
            endereco.logradouro = ControllerConsultaCep.endereco.logradouro;
             
            listaEnderecos.add(endereco);
            
        }
                
         
         return listaEnderecos;
  	}


    
}