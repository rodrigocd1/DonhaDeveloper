//Calculadoras de Custo
//09-17-2023
public class Calculators 
{
    /* Como executar
     * 
     * modeloCarro , valorVeiculoTabelaFipe , valorSeguro , mediaRevisao, valorMediaGasolina , kmPorLitro, KilometroRodadoAnual, valorPneu 
     * 
	 * Exemplo:
	 * Calculators.calcularCustoVeicularMensal('Prisma 2019' , 70000, 4000, 1500, 5.70, 12, 30000, 500, 60000);
	 * 
	 * verificar resultado do debug!!!
	 */
                                                          
    
   public static Decimal calcularCustoVeicularMensal( String modeloCarro,
                                                      Decimal valorVeiculoTabelaFipe , 
                                                      Decimal valorSeguro , 
                                                      Decimal valorMedioRevisao, 
                                                      Decimal valorMediaGasolina , 
                                                      Decimal kmPorLitro, 
                                                      Decimal KilometroRodadoAnual, 
                                                      Decimal valorPneu,
                                                      Decimal KMduracaoPneus)
   {
       
       //verify Variables
       if(  blankOrNull(valorVeiculoTabelaFipe)
          || blankOrNull(valorSeguro)
          || blankOrNull(valorMedioRevisao)
          || blankOrNull(valorMediaGasolina)
          || blankOrNull(kmPorLitro)
          || blankOrNull(KilometroRodadoAnual)
          || blankOrNull(valorPneu)
         )
       {
           system.debug( 'Ou amigão você ta tirando, se não manda o dado não tem milagre não Pow!' );
           return null;
       }              
       
       system.debug( '------Dados de Entrada ---------' );
       system.debug( 'Modelo:' 							 + modeloCarro );
       system.debug( 'Valor do Veiculo da Tabela Fipe: ' + valorVeiculoTabelaFipe );
       system.debug( 'Valor do Seguro:' 				 + valorSeguro );
       system.debug( 'Valor Médio da Revisao:' 			 + valorMedioRevisao );
       system.debug( 'Valor Médio da Gasolina:' 		 + valorMediaGasolina );
       system.debug( 'KM/L:' 							 + kmPorLitro );
       system.debug( 'Kilometros Rodados Anualmente:' 	 + KilometroRodadoAnual );
       system.debug( 'Valor do Pneu:' 					 + valorPneu );
       system.debug( 'KM duração do Pneus:' 			 + KMduracaoPneus );
       system.debug( '------------ dados de Saída -----' );       
       
       Decimal custoTotal = 0; 
       
       Decimal IPVAPorKM 		= BrazilianVehicleCost.IPVA( valorVeiculoTabelaFipe , 'SP' , KilometroRodadoAnual);
       Decimal pneusPorKM 		= BrazilianVehicleCost.custoKmRodadoPneu( valorPneu, KilometroRodadoAnual ,  KMduracaoPneus );
       Decimal gasolinaPorKM 	= BrazilianVehicleCost.custoGasolinaPorKM( valorMediaGasolina , kmPorLitro );
       Decimal seguroPorKM 		= BrazilianVehicleCost.custoSeguroPorKM( valorSeguro , KilometroRodadoAnual );
       Decimal revisaoPorKM 	= BrazilianVehicleCost.custoRevisaoPorKM( valorMedioRevisao, KilometroRodadoAnual );//Custo Revisão
       
       
       custoTotal += IPVAPorKM		;
       custoTotal += pneusPorKM		;
       custoTotal += gasolinaPorKM	;
       custoTotal += seguroPorKM	;
       custoTotal += revisaoPorKM	;
       
       system.debug('Custo por KM do seu veículo é ===> R$ ' + custoTotal  + '<===' );
       
       custoTotal = custoTotal * (KilometroRodadoAnual/12);
       
       system.debug('Custo Mensal Veículo ---> R$ ' + custoTotal.round().intValue() + ',00 <---'  );
       
       system.debug('Se você tivesse investido o valor desse carro na renda fixa no Brasil');
       
       Decimal dividendYeld 	= valorVeiculoTabelaFipe * 0.008;
       
       Integer rendimemtoMensal = dividendYeld.round().intValue() ;
       
       system.debug('Você estaria recebendo mensalmente pelo menos = R$ ' + rendimemtoMensal + ',00' );       
       
       return custoTotal;
   }
   
    
    
    
    private static Boolean blankOrNull( String text )
    {
        if( String.isBlank( text ) || String.isEmpty( text ) )
        {
        	return true;    
        }
        
        return false;
    }
    
    
    
    
    private static Boolean blankOrNull( Decimal value )
    {
        if( value == null )
        {
        	return true;    
        }
        
        return false;
    }
       

}