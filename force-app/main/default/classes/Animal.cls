// Classe abstrata Animal
public abstract class Animal {
    public String nome;
    
    // Construtor da classe Animal
    public Animal(String nome) {
        this.nome = nome;
    }
    
    // Método abstrato que deve ser implementado pelas subclasses
    public abstract void fazerSom();
}