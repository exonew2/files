use clap::Parser;

#[derive(Parser)]
#[command(name = "{{project_name}}", version)]
struct Cli {
    #[arg(short, long)]
    name: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    let cli = Cli::parse();
    println!("Hello from {{project_name}}!");
    if let Some(name) = cli.name {
        println!("Hello, {name}!");
    }
    Ok(())
}
