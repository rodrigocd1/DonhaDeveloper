/*********************************************************************************************************************************************************************

@description Classe de controle da visual force de Atualizar cadastro de conta
@author Avanxo
@date 12/06/2019
		
**********************************************************************************************************************************************************************/


public class ControllerAtualizarCadastroConta 
{ 
    public Account account 						         { get; set; } 
    public ConsultaServiceConsultarCep service			 { get; set; }
    public ConsultaServiceConsultarCep.Endereco endereco { get; set; }
    public String cepBusca 								 { get; set; }
    
 	/** 
    @description  método construtor que inicializa variáveis
    @param 
    @return 
    @author Rodrigo Donha
    @date 10/06/2019
	*/
    public ControllerAtualizarCadastroConta()
    {
        inicializarVariaveis();
    }
    
    
    
    
    private void inicializarVariaveis()
    {
        account	 	= new Account();
        cepBusca 	= '01317000';
        endereco 	= new ConsultaServiceConsultarCep.Endereco();
        service 	= new ConsultaServiceConsultarCep();
    }
    
    
    
     /** 
    @description  método que realiza a busca de CEP
    @param none
    @return none
    @author Rodrigo Donha
    @date 10/06/2019
	*/
    public void buscarCEP()
    {
        endereco = ConsultaServiceConsultarCep.buscarEnderecoPorCep( cepBusca );
    }
    
    
       
     /** 
    @description  método que realiza a busca de CEP
    @param none
    @return none
    @author Rodrigo Donha
    @date 10/06/2019
	*/
    @AuraEnabled
    public static String buscarCEPLightning( String cepBusca )
    {        
        return ConsultaServiceConsultarCep.buscarEnderecoPorCepJSON( cepBusca );
    }
}