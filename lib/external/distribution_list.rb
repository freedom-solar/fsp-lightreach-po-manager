class DistributionList
    def self.roms
        %w[
            rom@gofreedompower.com
            arom@gofreedompower.com
        ]
    end

    def self.site_assessors
        %w[siteassessors@gofreedompower.com]
    end

    def self.aroms
        %w[arom@gofreedompower.com]
    end

    def self.rpcs
        [ "rpc@gofreedompower.com" ]
    end

    def self.schedulers
        %w[schedulers@gofreedompower.com]
    end

    def self.cam
        %w[cam@gofreedompower.com]
    end

    def self.cam_leaders
        %w[
            mpadron@gofreedompower.com
            acoward@gofreedompower.com
            sturner@gofreedompower.com
            malaina@gofreedompower.com
        ]
    end

    def self.loan_team
        %w[shawn@gofreedompower.com mcondict@gofreedompower.com
           dfisk@gofreedompower.com vincentmann@gofreedompower.com]
    end

    def self.ar
        %w[ar@gofreedompower.com]
    end

    def self.legal
        %w[meredith@gofreedompower.com chrismcdonald@gofreedompower.com]
    end

    def self.customer_care
        %w[tthomas@gofreedompower.com sgaleana@gofreedompower.com]
    end

    def self.sales_assistance_team
        %w[
            aaron@gofreedompower.com
            asm@gofreedompower.com
            dkimbriel@gofreedompower.com
            vincentmann@gofreedompower.com
        ]
    end

    def self.m1_submittal_team
        %w[
            cam@gofreedompower.com
            rom@gofreedompower.com
            arom@gofreedompower.com
            josh@gofreedompower.com
            ltenbrook@gofreedompower.com
            mcondict@gofreedompower.com
            mmariano@gofreedompower.com
            dkimbriel@gofreedompower.com
            vincentmann@gofreedompower.com
            dfisk@gofreedompower.com
            chad@gofreedompower.com
            rhunter@gofreedompower.com
        ]
    end

    def self.inspections
        %w[inspections@gofreedompower.com]
    end

    def self.accounting_missing_payments
        [ "ar@gofreedompower.com" ]
    end

    def self.executives
        [
            "rhunter@gofreedompower.com"
        ]
    end

    def self.service_managers
        [
            "chance@gofreedompower.com",
            "jordanblair@gofreedompower.com",
            "zachsettles@gofreedompower.com"
        ]
    end

    def self.designers
        [ "designers@gofreedompower.com" ]
    end

    def self.lease_team
        [
            "aaron@gofreedompower.com",
            "chrismcdonald@gofreedompower.com",
            "dkimbriel@gofreedompower.com",
            "mcondict@gofreedompower.com",
            "chad@gofreedompower.com",
            "acoward@gofreedompower.com",
            "rom@gofreedompower.com",
            "vincentmann@gofreedompower.com"
        ]
    end

    def self.qct
        [ "quality@gofreedompower.com" ]
    end

    def self.monitoring
        [ "monitoring@gofreedompower.com" ]
    end

    def self.warehouse
        [ "WHmanagers@gofreedompower.com " ]
    end

    def self.regional_rom(region)
        region = "DFW" if region == "Dallas"
        rom_dict = {
            "Austin" => [ "jgarbo@gofreedompower.com", "cmorenomunoz@gofreedompower.com" ],
            "DFW" => [ "respana@gofreedompower.com", "jclark@gofreedompower.com" ],
            "Houston" => [ "marcusspicer@freedomsolarpower.com", "kjohnson@gofreedompower.com" ],
            "San Antonio" => [ "justinrose@gofreedompower.com", "jreyes@gofreedompower.com" ],
            "Orlando" => [ "carloslopez@gofreedompower.com" ],
            "Tampa" => [ "abronson@gofreedompower.com", "rachellethomas@gofreedompower.com " ]
        }
        rom_dict[region]
    end

    def self.punchlist_inspection_analysis
        %w[
            dkimbriel@gofreedompower.com
            chad@gofreedompower.com
            meredith@gofreedompower.com
            victoria@gofreedompower.com
            rhunter@gofreedompower.com
            doug@gofreedompower.com
            josh@freedomsolarpower.com
        ]
    end
end
