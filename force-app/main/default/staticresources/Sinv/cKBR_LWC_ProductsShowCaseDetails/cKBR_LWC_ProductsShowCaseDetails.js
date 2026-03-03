import { LightningElement, track, api } from 'lwc';
import contaCorrente from "@salesforce/label/c.CKBR_CL_ContaCorrente"; 
import percentualCDI from "@salesforce/label/c.CKBR_CL_PercentualCDI";
import { getDataHandler } from 'omnistudio/utility'; 
import horarioMovimentacao from "@salesforce/label/c.CKBR_CL_Horario_Movimentacao";
import horarioBR from "@salesforce/label/c.CKBR_CL_Horario"; 


export default class cKBR_LWC_ProductsShowCaseDetails extends LightningElement {
    @api investmentSelected;
    @api vitrineApiList;  
    @track nome = '';
    @track aplicacaoMinima = '';
    @track classificacaoTributaria = '';
    @track iRendimento = '';
    @track iof = '';
    @track risco = '';
    @track regasteMinimo = '';
    @track carencia = '';
    @track saldoMinimo = '';
    @track horarioAbertura = '';
    @track horarioFechamento = '';
    @track creditoContaCorrente = '';
    @track spinnerTable = false; 
    @api isShowDetails;
    @track horarioMovimentacao = '';

    label = {
        contaCorrente,
        percentualCDI, 
        horarioMovimentacao,
        horarioBR   
    }

    connectedCallback() {     
        console.log('this.investmentSelected' + this.investmentSelected.circleStyle); 
        this.nome = this.investmentSelected?.nome || 'LCI 5 anos'; 
        this.aplicacaoMinima = this.investmentSelected?.aplicacaoMinima || 'R$ 10.000,00';  
        this.horarioMovimentacao = this.investmentSelected?.horarioMovimentacao || '08h00 às 16h30';
        this.classificacaoTributaria = this.investmentSelected?.classificacaoTributaria || 'CDI/SELIC';
        this.iRendimento = this.investmentSelected?.iRendimento || 'de 22.5% a 15%';
        this.iof = this.investmentSelected?.iof || 'R$ 1.000,00';
        this.risco = this.investmentSelected?.risco || 'Muito baixo';
        this.creditoContaCorrente = this.investmentSelected?.creditoContaCorrente || '1 dia útil';
        this.regasteMinimo = 'R$ 10.000.00';    
        this.saldoMinimo =  'R$ 1000.00'   
        this.carencia =  'Longo Prazo'; 
 
        console.log('this.investmentSelected?.financialAccountId' + this.investmentSelected?.financialAccountId); 

        //this.getOmniStudioVIPDetails();  
        //this.getVIPHorarioMovimentacao();  
    }


    getVIPHorarioMovimentacao(){
        this.spinnerTable = true; 
         
        let optionsMap = {    
            "aRecordId" : this.investmentSelected?.financialAccountId,
        }    
        let vipRes = JSON.stringify({ 
            type: 'integrationprocedure',
            value: { 
                ipMethod: 'CKBR_VitrineProdutoHorarioMovimentacao', 
                inputMap: JSON.stringify(optionsMap), 
            },
        });
        getDataHandler(vipRes).then((data) => {
            
            setTimeout(() => {
                this.spinnerTable = false;
            }, 2000);
        }).catch((error) => {
            console.error('Error fetching data', error);
            this.showToastMessage('Erro', 'Erro no serviço da Integration Procedure de Renda Alta', 'error');
        });
    }

    getOmniStudioVIPDetails() {
        this.spinnerTable = true;
        let optionsMap = {    
            "aRecordId" : this.investmentSelected.financialAccountId 
        }   
        let vipRes = JSON.stringify({ 
            type: 'integrationprocedure',
            value: {
                ipMethod: 'CKBR_VitrineProdutoDetalhesRendaFixa', 
                inputMap: JSON.stringify(optionsMap), 
            },
        });
        getDataHandler(vipRes).then((data) => {
            
            //this.getVIPHorarioMovimentacao(); 
            setTimeout(() => {
                this.spinnerTable = false;
            }, 2000); 
            
        }).catch((error) => {
            console.error('Error fetching data', error);
            this.showToastMessage('Erro', 'Erro no serviço da Integration Procedure de Renda Alta', 'error');
        });
    }

    closeApply() {  
        this.isShowDetails = false;
        const selectedEvent = new CustomEvent("close", { detail: this.isShowDetails });
        this.dispatchEvent(selectedEvent);    
    }  

    handleApply() {      
        this.isShowAplicar = true;
        this.isShowDetails = false;  
        const selectedEvent = new CustomEvent("selected", { detail: this.isShowDetails });
        this.dispatchEvent(selectedEvent);    
    }
}