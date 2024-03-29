module Spree::Search
  class ProductIngredient < Spree::Core::Search::Base

    def retrieve_products
      @products_scope = get_base_scope
      @products_scope_without_name = get_base_scope_without_name_conditions
      curr_page = page || 1

      @products = @products_scope.includes([:master => :prices])
      unless Spree::Config.show_products_without_price
        @products = @products.where("spree_prices.amount IS NOT NULL").where("spree_prices.currency" => current_currency)
      end

      # search by name, descrription product
      #
      base_sql = "( spree_products.id in ( SELECT \"base_query\".subquery_product_id FROM (#{@products.select('spree_products.id as subquery_product_id').to_sql}) as base_query ))"

      # search products by ingredient lists
      #
      if (ingredient_sql = Spree::Ingredient.search_product_ids(keywords)).present?
        ingredient_sql = "( spree_products.id in ( SELECT \"base_query1\".subquery_product_id FROM (#{@products_scope_without_name.where(:id => ingredient_sql).select('spree_products.id as subquery_product_id').to_sql}) as base_query1 ))"
      else
        ingredient_sql = ''
      end

      # search products by review data
      #
      if (review_sql = review_subquery(keywords)).present?
        review_sql = "( spree_products.id in ( SELECT \"base_query2\".subquery_product_id FROM (#{@products_scope_without_name.where(:id => review_sql).select('spree_products.id as subquery_product_id').to_sql}) as base_query2 ))"
      else
        review_sql = ''
      end


      @products = Spree::Product.where([base_sql, ingredient_sql, review_sql ].select(&:present?).join(" OR "))
      @products = @products.page(curr_page).per(per_page)
    end

    def review_subquery(query)
      query = [query].compact.map(&:split).flatten.compact
      return nil if query.blank?
      first_keyword = query.shift
      like_sql = Spree::Review.arel_table[:title].matches("%#{first_keyword}%").or(Spree::Review.arel_table[:review].matches("%#{first_keyword}%"))
      query.each do |q|
        like_sql = like_sql.or(Spree::Review.arel_table[:title].matches("%#{q}%").or(Spree::Review.arel_table[:review].matches("%#{q}%")))
      end

      Spree::Review.select("spree_reviews.product_id").where(like_sql)
    end

    def get_base_scope_without_name_conditions
      base_scope = Spree::Product.active
      base_scope = base_scope.in_taxon(taxon) unless taxon.blank?
      base_scope = base_scope.on_hand unless Spree::Config[:show_zero_stock_products]
      base_scope = add_search_scopes(base_scope)
      base_scope
    end
  end
end
