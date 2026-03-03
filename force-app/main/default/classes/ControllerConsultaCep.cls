/*********************************************************************************************************************************************************************

@description Classe de controle da visual force de consultar CEP
@author Avanxo
@date 10/06/2019
		
**********************************************************************************************************************************************************************/



public class ControllerConsultaCep 
{
    public ConsultaServiceConsultarCep service			 { get; set; }
    public ConsultaServiceConsultarCep.Endereco endereco { get; set; }
    public String cepBusca 								 { get; set; }
    public String enderecoBusca 						 { get; set; }    
    
    
 	/** 
    @description  método construtor que inicializa variáveis
    @param 
    @return 
    @author Rodrigo Donha
    @date 10/06/2019
	*/
    public ControllerConsultaCep()
    {
        inicializarVariaveis();
    }
    
    
    
    /** 
    @description  método inicializador de variáveis
    @param 
    @return 
    @author Rodrigo Donha
    @date 10/06/2019
	*/
    private void inicializarVariaveis()
    {
        cepBusca = '01317000';
        endereco = new ConsultaServiceConsultarCep.Endereco();
        service = new ConsultaServiceConsultarCep();
        
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

}